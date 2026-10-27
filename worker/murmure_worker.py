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

VERSION = "0.1.0"
MAX_HEADER = 16_384
MAX_AUDIO_BYTES = 16 * 1024**3
CHUNK = 64 * 1024


class WorkerError(Exception):
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
                        raise WorkerError("This recording is already being submitted.")
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
                raise WorkerError("This recording is already being submitted.") from error
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


def status(root: Path, identifier: str) -> dict:
    directory = job_path(root, identifier)
    path = directory / "status.json"
    if not path.exists():
        return {"state": "missing", "id": identifier}
    result = read_json(path)
    if result["state"] == "completed":
        result["transcript"] = read_json(directory / "transcript.json")
    return result


def start_detached(root: Path, identifier: str) -> None:
    directory = job_path(root, identifier)
    arguments = [sys.executable, str(Path(__file__).resolve()), "run-job", "--root", str(root), "--id", identifier]
    kwargs = {"stdin": subprocess.DEVNULL, "close_fds": True}
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    with (directory / "worker.log").open("ab", buffering=0) as log:
        subprocess.Popen(arguments, stdout=log, stderr=log, **kwargs)


def submit(root: Path, header: dict, source: BinaryIO) -> dict:
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
        state_path = directory / "status.json"
        atomic_json(state_path, {"id": identifier, "state": "receiving"})
        temporary = directory / "audio.partial"
        try:
            with temporary.open("wb") as audio:
                copy_exact(source, audio, size)
                audio.flush(); os.fsync(audio.fileno())
            os.replace(temporary, directory / "audio.m4a")
            atomic_json(directory / "request.json", options)
            atomic_json(state_path, {"id": identifier, "state": "queued"})
            start_detached(root, identifier)
        except Exception:
            atomic_json(state_path, {"id": identifier, "state": "failed", "error": "Submission was interrupted. Retry from the Mac."})
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


def transcribe(path: Path, options: dict) -> dict:
    try:
        import ctranslate2
        from faster_whisper import WhisperModel
    except ImportError as error:
        raise WorkerError("Transcription is not installed in this Python environment. Install worker/requirements.txt first.") from error
    device = options["device"]
    if device == "auto":
        device = "cuda" if ctranslate2.get_cuda_device_count() else "cpu"
    model = WhisperModel(options["model"], device=device, compute_type="float16" if device == "cuda" else "int8", cpu_threads=min(4, os.cpu_count() or 1))
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
        try:
            import torch
            from pyannote.audio import Pipeline
        except ImportError as error:
            raise WorkerError("Speaker labels need worker/requirements-diarization.txt on the processing computer.") from error
        # Credentials remain on the processing computer; never send them from the app.
        token_file = os.environ.get("MURMURE_HF_TOKEN_FILE")
        token = Path(token_file).expanduser().read_text(encoding="utf-8").strip() if token_file else True
        pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-community-1", token=token)
        pipeline.to(torch.device(device))
        diarized = pipeline(str(path))
        annotation = diarized.exclusive_speaker_diarization
        turns = [(float(turn.start), float(turn.end), label) for turn, _, label in annotation.itertracks(yield_label=True)]
        segments = assign_speakers(segments, turns)
    for segment in segments:
        segment.pop("words", None)
        if not (math.isfinite(segment["start"]) and math.isfinite(segment["end"])):
            raise WorkerError("The model returned invalid timestamps.")
    return {"language": info.language, "segments": segments}


def run_job(root: Path, identifier: str) -> None:
    directory = job_path(root, identifier)
    try:
        with file_lock(directory / "run.lock", blocking=False):
            if status(root, identifier)["state"] == "completed":
                return
            # One model process at a time per worker root, even across submissions.
            with file_lock(root / "engine.lock"):
                atomic_json(directory / "status.json", {"id": identifier, "state": "running"})
                result = transcribe(directory / "audio.m4a", read_json(directory / "request.json"))
                atomic_json(directory / "transcript.json", result)
                atomic_json(directory / "status.json", {"id": identifier, "state": "completed"})
    except Exception as error:
        message = str(error) if isinstance(error, WorkerError) else f"Transcription failed ({type(error).__name__}). Check the model, dependencies and any required model access on the processing computer."
        atomic_json(directory / "status.json", {"id": identifier, "state": "failed", "error": message})
        print(message, file=sys.stderr)


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
        return {"state": "ready", "version": VERSION,
                "transcriptionInstalled": importlib.util.find_spec("faster_whisper") is not None}
    if operation == "status":
        return status(root, header.get("id"))
    if operation == "submit":
        return submit(root, header, source)
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
