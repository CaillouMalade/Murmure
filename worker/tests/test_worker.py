import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
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


if __name__ == "__main__":
    unittest.main()
