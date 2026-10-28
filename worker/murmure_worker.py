#!/usr/bin/env python3
"""One-shot, streaming JSON/binary worker. No web server and no model at idle.

rpc: read one UTF-8 JSON line, then exactly `bytes` audio bytes for submit.
The response is one JSON object. Inference runs in a detached child process.
"""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import BinaryIO
import uuid

VERSION = "0.4.1"
MAX_HEADER = 16_384
MAX_AUDIO_BYTES = 16 * 1024**3
CHUNK = 64 * 1024
STALE_SECONDS = 120


class WorkerError(Exception):
    pass


class LockBusy(WorkerError):
    pass


def atomic_json(path: Path, value: dict) -> None:
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, allow_nan=False)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_status(directory: Path, state: str, **fields) -> None:
    atomic_json(directory / "status.json", {"id": directory.name, "state": state, "updatedAt": time.time(), **fields})


def failure_message(error: Exception) -> str:
    return str(error) if isinstance(error, WorkerError) else f"Transcription failed ({type(error).__name__}). Check the model, dependencies and any required model access on the processing computer."


def job_path(root: Path, identifier: str) -> Path:
    if not isinstance(identifier, str):
        raise WorkerError("A recording identifier is required.")
    try:
        if str(uuid.UUID(identifier)) != identifier:
            raise ValueError()
    except ValueError as error:
        raise WorkerError("Invalid recording identifier.") from error
    directory = root / identifier
    if directory.is_symlink():
        raise WorkerError("A recording directory must not be a symbolic link.")
    return directory


def validated_options(raw: dict) -> dict:
    if not isinstance(raw, dict):
        raise WorkerError("Invalid transcription options.")
    model = raw.get("model", "small")
    language = raw.get("language", "")
    device = raw.get("device", "auto")
    if not isinstance(model, str) or not model or len(model) > 512:
        raise WorkerError("Choose a model name or a local model directory.")
    if not isinstance(language, str) or (language and (not language.isalpha() or len(language) > 8)):
        raise WorkerError("Language must be empty or a language code such as en or fr.")
    if model.endswith(".en") and language and language != "en":
        raise WorkerError("An English-only .en model cannot transcribe that language. Choose a multilingual model such as small, or select en.")
    if device not in ("auto", "cpu", "cuda"):
        raise WorkerError("Device must be auto, cpu or cuda.")
    for flag in ("diarization", "timestamps"):
        if flag in raw and not isinstance(raw[flag], bool):
            raise WorkerError("Transcription switches must be booleans.")
    return {"model": model, "language": language, "device": device,
            "diarization": raw.get("diarization", False), "timestamps": raw.get("timestamps", True)}


@contextlib.contextmanager
def file_lock(path: Path, *, blocking: bool = True):
    """OS releases the lock after a crash. Keep the file to avoid inode races."""
    with path.open("a+b") as handle:
        if os.name == "nt":
            import msvcrt
            if path.stat().st_size == 0:
                handle.write(b"\0"); handle.flush()
            while True:
                try:
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError:
                    if not blocking:
                        raise LockBusy("This recording is already being handled by another worker.")
                    time.sleep(1)  # Only queued workers on the processing computer wait.
            try:
                yield
            finally:
                handle.seek(0); msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
            except BlockingIOError as error:
                raise LockBusy("This recording is already being handled by another worker.") from error
            try:
                yield
            finally:
                fcntl.flock(handle, fcntl.LOCK_UN)


def copy_exact(source: BinaryIO, destination: BinaryIO, size: int) -> None:
    remaining = size
    while remaining:
        block = source.read(min(CHUNK, remaining))
        if not block:
            raise WorkerError("Audio transfer was interrupted. The original recording is still on the Mac.")
        destination.write(block)
        remaining -= len(block)


def status(root: Path, identifier: str, *, check_stalled: bool = True) -> dict:
    directory = job_path(root, identifier)
    path = directory / "status.json"
    if not path.exists():
        return {"state": "missing", "id": identifier}
    result = read_json(path)
    if check_stalled and result["state"] in ("receiving", "queued", "running"):
        def stale(value):
            return time.time() - value.get("updatedAt", path.stat().st_mtime) > STALE_SECONDS
        if stale(result):
            lock_name = "submit.lock" if result["state"] == "receiving" else "run.lock"
            try:
                with file_lock(directory / lock_name, blocking=False):
                    # Re-read under the lock, so a late result cannot be overwritten.
                    current = read_json(path)
                    if current["state"] == result["state"] and stale(current):
                        write_status(directory, "failed", error="The worker stopped before finishing. The recording is kept; retry after checking the processing computer.")
                    result = read_json(path)
            except LockBusy:
                pass  # A real live/queued process holds its lock, even for a long job.
    if result["state"] == "completed":
        result["transcript"] = read_json(directory / "transcript.json")
    return result


def detached_process_options(platform: str | None = None) -> dict:
    if (platform or sys.platform) == "win32":
        # Win32 constants: DETACHED_PROCESS, CREATE_NEW_PROCESS_GROUP,
        # CREATE_BREAKAWAY_FROM_JOB. No silent fallback into the SSH job object.
        return {"creationflags": 0x00000008 | 0x00000200 | 0x01000000}
    return {"start_new_session": True}


def spawn_detached(arguments: list[str], log: BinaryIO) -> subprocess.Popen:
    try:
        return subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                close_fds=True, **detached_process_options())
    except OSError as error:
        if sys.platform == "win32" and getattr(error, "winerror", None) == 5:
            raise WorkerError("Windows refused to start a job outside this SSH session. Use an OpenSSH host that permits process breakaway, or a separately configured worker host. No job was started and the recording is kept.") from error
        raise


def start_detached(root: Path, identifier: str) -> None:
    directory = job_path(root, identifier)
    arguments = [sys.executable, str(Path(__file__).resolve()), "run-job", "--root", str(root), "--id", identifier]
    with (directory / "worker.log").open("ab", buffering=0) as log:
        spawn_detached(arguments, log)


def submit(root: Path, header: dict, source: BinaryIO, *, deferred: bool = True) -> dict:
    identifier = header.get("id")
    directory = job_path(root, identifier)
    size = header.get("bytes")
    if isinstance(size, bool) or not isinstance(size, int) or not 0 < size <= MAX_AUDIO_BYTES:
        raise WorkerError("Recording must contain audio and be smaller than 16 GiB.")
    options = validated_options(header.get("options", {}))
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with file_lock(directory / "submit.lock", blocking=False):
        existing = status(root, identifier)
        if existing["state"] in ("queued", "running", "completed"):
            with open(os.devnull, "wb") as sink:
                copy_exact(source, sink, size)
            return existing
        write_status(directory, "receiving")
        temporary = directory / "audio.partial"
        try:
            with temporary.open("wb") as audio:
                copy_exact(source, audio, size)
                audio.flush(); os.fsync(audio.fileno())
            os.replace(temporary, directory / "audio.m4a")
            atomic_json(directory / "request.json", options)
            write_status(directory, "queued")
            if deferred:
                start_detached(root, identifier)
        except Exception as error:
            write_status(directory, "failed", error=failure_message(error))
            raise
    return {"id": identifier, "state": "queued"}


def speaker_at(start: float, end: float, turns: list[tuple[float, float, str]]) -> str | None:
    scores: dict[str, float] = {}
    for left, right, speaker in turns:
        overlap = max(0.0, min(end, right) - max(start, left))
        if overlap:
            scores[speaker] = scores.get(speaker, 0.0) + overlap
    return max(scores, key=scores.get) if scores else None


def assign_speakers(segments: list[dict], turns: list[tuple[float, float, str]]) -> list[dict]:
    result: list[dict] = []
    for segment in segments:
        words = segment.get("words") or [{"start": segment["start"], "end": segment["end"], "text": segment["text"]}]
        for word in words:
            speaker = speaker_at(word["start"], word["end"], turns)
            if result and result[-1]["speaker"] == speaker and word["start"] - result[-1]["end"] < 1.5:
                result[-1]["text"] += word["text"]
                result[-1]["end"] = word["end"]
            else:
                result.append({"start": word["start"], "end": word["end"], "text": word["text"], "speaker": speaker})
    return result


def load_model(options: dict, *, local_files_only: bool = False):
    try:
        import ctranslate2
        from faster_whisper import WhisperModel
    except ImportError as error:
        raise WorkerError("Transcription is not installed in this Python environment. Install worker/requirements.txt first.") from error
    device = options["device"]
    try:
        if device == "auto":
            device = "cuda" if ctranslate2.get_cuda_device_count() else "cpu"
        model = WhisperModel(options["model"], device=device, compute_type="float16" if device == "cuda" else "int8",
                             cpu_threads=min(4, os.cpu_count() or 1), local_files_only=local_files_only)
        return model, device
    except Exception as error:
        if local_files_only:
            raise WorkerError("The selected model is not ready for dictation. Use Download & check model in Murmure Setup on the same worker account, or select an installed CTranslate2 model directory. If CUDA fails, select CPU and check again.") from error
        raise WorkerError("The selected Whisper model could not load. Check its name or CTranslate2 directory and the processing computer's network access. For a CUDA setup error, select CPU or install compatible CUDA/cuDNN libraries, then try Download & check model again.") from error


def load_diarizer(device: str):
    try:
        import torch
        from pyannote.audio import Pipeline
    except ImportError as error:
        raise WorkerError("Speaker labels need worker/requirements-diarization.txt on the processing computer.") from error
    try:
        # Credentials remain on the processing computer; never send them from the app.
        token_file = os.environ.get("MURMURE_HF_TOKEN_FILE")
        token = Path(token_file).expanduser().read_text(encoding="utf-8").strip() if token_file else True
        pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-community-1", token=token)
        pipeline.to(torch.device(device))
        return pipeline
    except Exception as error:
        raise WorkerError("The speaker-label model could not load. Accept the Community-1 model conditions and sign in to Hugging Face on the processing computer; also check its FFmpeg and device setup.") from error


def prepare_model(root: Path, options: dict) -> dict:
    try:
        with file_lock(root / "engine.lock", blocking=False):
            model, device = load_model(options)
            try:
                # Exercise decoding as well as weight loading: CUDA discovery
                # alone does not prove the cuDNN runtime is usable.
                import numpy as np
                iterator, _ = model.transcribe(np.zeros(16000, dtype=np.float32), language=options["language"] or "en",
                                              beam_size=1, vad_filter=False)
                list(iterator)
            except Exception as error:
                raise WorkerError("The model loaded but its audio check failed. Check the language and audio runtime; for a CUDA error, select CPU and check again.") from error
            finally:
                del model
            if options["diarization"]:
                pipeline = load_diarizer(device)
                del pipeline
            return {"state": "ready", "version": VERSION, "protocolVersion": 1,
                    "model": options["model"], "device": device}
    except LockBusy as error:
        raise WorkerError("The worker is processing another recording. Wait for it to finish before preparing a model.") from error


def transcribe(path: Path, options: dict, *, local_files_only: bool = False) -> dict:
    model, device = load_model(options, local_files_only=local_files_only)
    iterator, info = model.transcribe(str(path), language=options["language"] or None,
                                     beam_size=5, vad_filter=True, word_timestamps=options["diarization"])
    segments = []
    for item in iterator:
        segment = {"start": float(item.start), "end": float(item.end), "text": item.text, "speaker": None}
        if options["diarization"] and item.words:
            segment["words"] = [{"start": float(word.start), "end": float(word.end), "text": word.word} for word in item.words]
        segments.append(segment)
    del model  # Do not retain the transcription model while running diarization.
    if options["diarization"]:
        pipeline = load_diarizer(device)
        diarized = pipeline(str(path))
        annotation = diarized.exclusive_speaker_diarization
        turns = [(float(turn.start), float(turn.end), label) for turn, _, label in annotation.itertracks(yield_label=True)]
        segments = assign_speakers(segments, turns)
    for segment in segments:
        segment.pop("words", None)
        if not (math.isfinite(segment["start"]) and math.isfinite(segment["end"])):
            raise WorkerError("The model returned invalid timestamps.")
    return {"language": info.language, "segments": segments}


def run_job(root: Path, identifier: str, *, wait_for_engine: bool = True) -> None:
    directory = job_path(root, identifier)
    try:
        with file_lock(directory / "run.lock", blocking=False):
            if status(root, identifier, check_stalled=False)["state"] not in ("queued", "running"):
                return
            try:
                # Hold run.lock even while queued, so long waits are not called stalled.
                with file_lock(root / "engine.lock", blocking=wait_for_engine):
                    write_status(directory, "running")
                    with contextlib.redirect_stdout(sys.stderr):
                        result = transcribe(directory / "audio.m4a", read_json(directory / "request.json"), local_files_only=not wait_for_engine)
                    atomic_json(directory / "transcript.json", result)
                    write_status(directory, "completed")
            except Exception as error:
                if isinstance(error, LockBusy) and not wait_for_engine:
                    error = WorkerError("The remote model is busy with another recording. Dictation was saved; try again when it finishes, or select on-device dictation in Settings.")
                message = failure_message(error)
                write_status(directory, "failed", error=message)
                print(message, file=sys.stderr)
    except LockBusy:
        return  # A duplicate runner must never overwrite the live runner's status.


def module_available(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def rpc(source: BinaryIO) -> dict:
    raw = source.readline(MAX_HEADER + 1)
    if len(raw) > MAX_HEADER or not raw.endswith(b"\n"):
        raise WorkerError("Invalid request header.")
    header = json.loads(raw)
    if not isinstance(header, dict):
        raise WorkerError("Request must be a JSON object.")
    raw_root = header.get("root", "~/.murmure")
    if not isinstance(raw_root, str) or not raw_root.strip():
        raise WorkerError("Choose a worker data directory.")
    root = Path(raw_root).expanduser().resolve()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    operation = header.get("op")
    if operation == "probe":
        return {"state": "ready", "version": VERSION, "protocolVersion": 1,
                "transcriptionInstalled": module_available("faster_whisper"),
                "diarizationInstalled": module_available("pyannote.audio"),
                "supportsModelPreparation": True}
    if operation == "prepare":
        options = validated_options(header.get("options", {}))
        with contextlib.redirect_stdout(sys.stderr):
            return prepare_model(root, options)
    if operation == "status":
        return {**status(root, header.get("id")), "protocolVersion": 1}
    if operation == "submit":
        return {**submit(root, header, source), "protocolVersion": 1}
    if operation == "transcribe":
        # Foreground SSH lifetime: one upload, one inference, one response.
        # Never leave a detached dictation or poll an engine queue from the Mac.
        result = submit(root, header, source, deferred=False)
        if result["state"] != "completed":
            run_job(root, header.get("id"), wait_for_engine=False)
        return {**status(root, header.get("id")), "protocolVersion": 1}
    raise WorkerError("Unknown worker operation.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("rpc", "run-job"))
    parser.add_argument("--root")
    parser.add_argument("--id")
    arguments = parser.parse_args()
    if arguments.operation == "run-job":
        if not arguments.root or not arguments.id:
            parser.error("run-job requires --root and --id")
        run_job(Path(arguments.root), arguments.id)
        return
    try:
        result = rpc(sys.stdin.buffer)
    except Exception as error:
        message = str(error) if isinstance(error, WorkerError) else f"Worker request failed ({type(error).__name__})."
        result = {"state": "error", "error": message}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False), flush=True)


if __name__ == "__main__":
    main()
