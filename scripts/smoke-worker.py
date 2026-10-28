"""Opt-in real CPU inference test with supplied synthetic speech, no credentials.

Run with the worker venv. Unlike unit tests this downloads a public model on
first use. Set HF_HOME outside source files; never supply private audio here.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "worker"))
import murmure_worker as worker


def make_aac(source: Path, destination: Path):
    import av
    with av.open(str(source)) as incoming, av.open(str(destination), "w", format="ipod") as outgoing:
        stream = outgoing.add_stream("aac", rate=16_000)
        stream.layout = "mono"; stream.bit_rate = 64_000
        resampler = av.AudioResampler(format="fltp", layout="mono", rate=16_000)
        for frame in incoming.decode(audio=0):
            for converted in resampler.resample(frame):
                converted.pts = None
                for packet in stream.encode(converted): outgoing.mux(packet)
        for converted in resampler.resample(None):
            converted.pts = None
            for packet in stream.encode(converted): outgoing.mux(packet)
        for packet in stream.encode(None): outgoing.mux(packet)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--expected", nargs="+", default=["recording", "computer"])
    parser.add_argument("--model", default="tiny.en")
    parser.add_argument("--foreground", action="store_true", help="Exercise v0.3 quick dictation through a real RPC subprocess.")
    arguments = parser.parse_args()
    root = arguments.root.resolve(); root.mkdir(parents=True, exist_ok=True)
    identifier = str(uuid.uuid4())
    encoded = root / (identifier + "-input.m4a")
    make_aac(arguments.audio, encoded)
    options = {"model": arguments.model, "language": "en", "device": "cpu", "timestamps": True, "diarization": False}
    header = {"op": "submit", "root": str(root), "id": identifier, "bytes": encoded.stat().st_size, "options": options}
    if arguments.foreground:
        header["op"] = "transcribe"
        with tempfile.TemporaryFile() as wire, encoded.open("rb") as audio:
            wire.write(json.dumps(header).encode() + b"\n")
            shutil.copyfileobj(audio, wire, length=65_536); wire.seek(0)
            result = subprocess.run([sys.executable, str(Path(worker.__file__)), "rpc"], stdin=wire, capture_output=True, timeout=180, check=True)
        status = json.loads(result.stdout)
        assert status["state"] == "completed", status
        text = " ".join(segment["text"].strip() for segment in status["transcript"]["segments"])
        assert all(word.casefold() in text.casefold() for word in arguments.expected), text
        print(json.dumps({"passed": True, "foreground": True, "model": arguments.model, "device": "cpu", "job": identifier, "transcript": text}, ensure_ascii=False))
        return
    children = []
    original_spawn = worker.spawn_detached

    def capture_process_handle(*args, **kwargs):
        # Keep only a waitable handle. The real launcher/model run unchanged.
        child = original_spawn(*args, **kwargs); children.append(child); return child

    worker.spawn_detached = capture_process_handle
    try:
        with tempfile.TemporaryFile() as wire, encoded.open("rb") as audio:
            wire.write(json.dumps(header).encode() + b"\n")
            shutil.copyfileobj(audio, wire, length=65_536); wire.seek(0)
            response = worker.rpc(wire)
    finally:
        worker.spawn_detached = original_spawn
    assert response["state"] == "queued", response
    assert len(children) == 1
    try:
        children[0].wait(timeout=180)
    except subprocess.TimeoutExpired:
        children[0].terminate()
        try: children[0].wait(timeout=10)
        except subprocess.TimeoutExpired: children[0].kill(); children[0].wait()
        raise
    request = json.dumps({"op": "status", "root": str(root), "id": identifier}).encode() + b"\n"
    result = subprocess.run([sys.executable, str(Path(worker.__file__)), "rpc"], input=request, capture_output=True, check=True)
    status = json.loads(result.stdout)
    assert status["state"] == "completed", status
    text = " ".join(segment["text"].strip() for segment in status["transcript"]["segments"])
    assert all(word.casefold() in text.casefold() for word in arguments.expected), text
    print(json.dumps({"passed": True, "model": arguments.model, "device": "cpu", "job": identifier,
                      "language": status["transcript"]["language"], "transcript": text}, ensure_ascii=False))


if __name__ == "__main__":
    main()
