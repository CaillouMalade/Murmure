import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import murmure_worker as worker


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.identifier = str(uuid.uuid4())

    def header(self, data=b"audio"):
        return {"op": "submit", "root": str(self.root), "id": self.identifier, "bytes": len(data), "options": {}}

    def test_rejects_traversal_and_noncanonical_identifiers(self):
        for value in ("../escape", "..", "", None, str(uuid.uuid4()).upper()):
            with self.assertRaises(worker.WorkerError):
                worker.job_path(self.root, value)

    def test_streaming_submission_and_idempotent_retry(self):
        data = b"a" * (worker.CHUNK * 3 + 123)
        with patch.object(worker, "start_detached") as start:
            response = worker.submit(self.root, self.header(data), io.BytesIO(data))
            self.assertEqual(response["state"], "queued")
            self.assertEqual((self.root / self.identifier / "audio.m4a").read_bytes(), data)
            duplicate = io.BytesIO(data)
            worker.submit(self.root, self.header(data), duplicate)
            self.assertEqual(duplicate.read(), b"")
            start.assert_called_once()

    def test_partial_upload_is_failed_and_can_be_retried(self):
        with patch.object(worker, "start_detached") as start:
            with self.assertRaises(worker.WorkerError):
                worker.submit(self.root, self.header(b"long recording"), io.BytesIO(b"short"))
            self.assertEqual(worker.status(self.root, self.identifier)["state"], "failed")
            start.assert_not_called()
            worker.submit(self.root, self.header(), io.BytesIO(b"audio"))
            self.assertEqual(worker.status(self.root, self.identifier)["state"], "queued")

    def test_diarization_splits_a_segment_when_speaker_changes(self):
        segments = [{"start": 0, "end": 2, "text": " Hello there", "words": [
            {"start": 0, "end": 0.8, "text": " Hello"}, {"start": 1.1, "end": 2, "text": " there"}]}]
        output = worker.assign_speakers(segments, [(0, 1, "A"), (1, 3, "B")])
        self.assertEqual([segment["speaker"] for segment in output], ["A", "B"])
        self.assertEqual("".join(segment["text"] for segment in output), " Hello there")

    def test_run_job_writes_result_before_completed_state(self):
        with patch.object(worker, "start_detached"):
            worker.submit(self.root, self.header(), io.BytesIO(b"audio"))
        transcript = {"language": "en", "segments": [{"start": 0, "end": 1, "text": "Hello", "speaker": None}]}
        with patch.object(worker, "transcribe", return_value=transcript):
            worker.run_job(self.root, self.identifier)
        self.assertEqual(worker.status(self.root, self.identifier)["transcript"], transcript)

    def test_foreground_dictation_returns_result_without_detached_process(self):
        header = {**self.header(), "op": "transcribe"}
        source = io.BytesIO(json.dumps(header).encode() + b"\n" + b"audio")
        transcript = {"language": "en", "segments": [{"start": 0, "end": 1, "text": " Dictation", "speaker": None}]}
        with patch.object(worker, "start_detached") as start, patch.object(worker, "transcribe", return_value=transcript) as transcribe:
            result = worker.rpc(source)
        start.assert_not_called()
        self.assertEqual(result["state"], "completed")
        self.assertEqual(result["transcript"], transcript)
        self.assertEqual(result["protocolVersion"], 1)
        self.assertEqual((self.root / self.identifier / "audio.m4a").read_bytes(), b"audio")
        self.assertTrue(transcribe.call_args.kwargs["local_files_only"])

    def test_prepare_checks_synthetic_audio_and_optional_diarization_without_job(self):
        options = worker.validated_options({"model": "small", "language": "fr", "diarization": True})
        model = types.SimpleNamespace(transcribe=lambda *a, **k: (iter([]), None))
        numpy = types.SimpleNamespace(zeros=lambda *a, **k: "synthetic-silence", float32="float32")
        request = {"op": "prepare", "root": str(self.root), "options": options}
        with patch.object(worker, "load_model", return_value=(model, "cpu")) as load, \
             patch.object(worker, "load_diarizer") as diarizer, patch.dict(sys.modules, {"numpy": numpy}):
            result = worker.rpc(io.BytesIO(json.dumps(request).encode() + b"\n"))
        self.assertEqual(result["state"], "ready")
        self.assertEqual(result["model"], "small")
        self.assertEqual(result["device"], "cpu")
        load.assert_called_once_with(options)
        diarizer.assert_called_once_with("cpu")
        self.assertFalse((self.root / self.identifier).exists())

    def test_prepare_refuses_busy_engine_without_loading_a_model(self):
        with worker.file_lock(self.root / "engine.lock"), patch.object(worker, "load_model") as load:
            with self.assertRaisesRegex(worker.WorkerError, "processing another recording"):
                worker.prepare_model(self.root, worker.validated_options({}))
        load.assert_not_called()

    def test_missing_cached_dictation_model_has_actionable_sanitized_error(self):
        fake_whisper = types.SimpleNamespace(WhisperModel=lambda *a, **k: (_ for _ in ()).throw(RuntimeError("private-credential")))
        fake_translate = types.SimpleNamespace(get_cuda_device_count=lambda: 0)
        with patch.dict(sys.modules, {"faster_whisper": fake_whisper, "ctranslate2": fake_translate}):
            with self.assertRaisesRegex(worker.WorkerError, "Download & check model") as error:
                worker.load_model(worker.validated_options({}), local_files_only=True)
        self.assertNotIn("private-credential", str(error.exception))

    def test_english_only_model_rejects_explicit_other_language(self):
        with self.assertRaisesRegex(worker.WorkerError, "English-only"):
            worker.validated_options({"model": "tiny.en", "language": "fr"})

    def test_foreground_dictation_fails_fast_when_engine_is_busy(self):
        with patch.object(worker, "start_detached") as start:
            worker.submit(self.root, self.header(), io.BytesIO(b"audio"), deferred=False)
        start.assert_not_called()
        with worker.file_lock(self.root / "engine.lock"), patch.object(worker, "transcribe") as transcribe:
            worker.run_job(self.root, self.identifier, wait_for_engine=False)
        transcribe.assert_not_called()
        result = worker.status(self.root, self.identifier)
        self.assertEqual(result["state"], "failed")
        self.assertIn("busy", result["error"])
        self.assertTrue((self.root / self.identifier / "audio.m4a").exists())

    def test_foreground_retry_returns_saved_result_without_new_inference(self):
        transcript = {"language": "en", "segments": []}
        with patch.object(worker, "start_detached"), patch.object(worker, "transcribe", return_value=transcript) as transcribe:
            for _ in range(2):
                source = io.BytesIO(json.dumps({**self.header(), "op": "transcribe"}).encode() + b"\n" + b"audio")
                self.assertEqual(worker.rpc(source)["state"], "completed")
        transcribe.assert_called_once()

    def test_failure_is_reported_without_exception_secrets(self):
        with patch.object(worker, "start_detached"):
            worker.submit(self.root, self.header(), io.BytesIO(b"audio"))
        with patch.object(worker, "transcribe", side_effect=RuntimeError("private-credential")):
            worker.run_job(self.root, self.identifier)
        response = worker.status(self.root, self.identifier)
        self.assertEqual(response["state"], "failed")
        self.assertNotIn("private-credential", response["error"])

    def test_model_integration_without_downloads(self):
        segment = types.SimpleNamespace(start=0, end=1.5, text=" Hello", words=None)
        model = types.SimpleNamespace(transcribe=lambda *args, **kwargs: (iter([segment]), types.SimpleNamespace(language="en")))
        fake_whisper = types.SimpleNamespace(WhisperModel=lambda *args, **kwargs: model)
        fake_translate = types.SimpleNamespace(get_cuda_device_count=lambda: 0)
        with patch.dict(sys.modules, {"faster_whisper": fake_whisper, "ctranslate2": fake_translate}):
            result = worker.transcribe(self.root / "audio.m4a", worker.validated_options({}))
        self.assertEqual(result["segments"][0]["text"], " Hello")

    def test_protocol_in_a_real_subprocess(self):
        request = json.dumps({"op": "status", "root": str(self.root), "id": self.identifier}).encode() + b"\n"
        result = subprocess.run([sys.executable, str(Path(worker.__file__)), "rpc"], input=request, capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout)["state"], "missing")

    def test_validation_does_not_accept_truthy_strings(self):
        with self.assertRaises(worker.WorkerError):
            worker.validated_options({"diarization": "false"})
        with self.assertRaises(worker.WorkerError):
            worker.submit(self.root, {**self.header(), "bytes": True}, io.BytesIO(b"a"))

    def make_stale(self, state="queued"):
        directory = worker.job_path(self.root, self.identifier)
        directory.mkdir(exist_ok=True)
        worker.atomic_json(directory / "status.json", {"id": self.identifier, "state": state,
                           "updatedAt": time.time() - worker.STALE_SECONDS - 10})
        return directory

    def test_dead_worker_becomes_retryable_and_never_restarts_itself(self):
        directory = self.make_stale()
        with patch.object(worker, "start_detached") as launch:
            result = worker.status(self.root, self.identifier)
        self.assertEqual(result["state"], "failed")
        self.assertIn("stopped before finishing", result["error"])
        launch.assert_not_called()
        self.assertTrue((directory / "status.json").is_file())

    def test_live_worker_is_not_stalled_even_after_a_long_queue_wait(self):
        directory = self.make_stale()
        with worker.file_lock(directory / "run.lock"):
            self.assertEqual(worker.status(self.root, self.identifier)["state"], "queued")

    def test_partial_upload_stall_uses_the_submission_lock(self):
        directory = self.make_stale("receiving")
        with worker.file_lock(directory / "submit.lock"):
            self.assertEqual(worker.status(self.root, self.identifier)["state"], "receiving")
        self.assertEqual(worker.status(self.root, self.identifier)["state"], "failed")

    def test_duplicate_runner_cannot_mark_the_real_runner_as_failed(self):
        directory = self.make_stale("running")
        with worker.file_lock(directory / "run.lock"), patch.object(worker, "transcribe") as infer:
            worker.run_job(self.root, self.identifier)
            self.assertEqual(worker.status(self.root, self.identifier)["state"], "running")
            infer.assert_not_called()

    def test_windows_detach_requests_breakaway_without_changing_posix(self):
        self.assertEqual(worker.detached_process_options("win32")["creationflags"] & 0x01000000, 0x01000000)
        self.assertEqual(worker.detached_process_options("darwin"), {"start_new_session": True})

    def test_windows_refusal_is_clear_and_does_not_retry_a_weaker_launch(self):
        error = OSError("access denied")
        error.winerror = 5
        with patch.object(worker.sys, "platform", "win32"), patch.object(worker.subprocess, "Popen", side_effect=error) as launch:
            with self.assertRaisesRegex(worker.WorkerError, "Windows refused"):
                worker.spawn_detached(["python", "worker.py"], io.BytesIO())
        launch.assert_called_once()

    def test_probe_reports_dependencies_without_importing_the_model_runtime(self):
        request = {"op": "probe", "root": str(self.root)}
        with patch.object(worker, "module_available", return_value=False), patch.object(worker, "transcribe") as infer:
            result = worker.rpc(io.BytesIO(json.dumps(request).encode() + b"\n"))
        self.assertEqual(result["protocolVersion"], 1)
        self.assertFalse(result["transcriptionInstalled"])
        self.assertFalse(result["diarizationInstalled"])
        infer.assert_not_called()


if __name__ == "__main__":
    unittest.main()
