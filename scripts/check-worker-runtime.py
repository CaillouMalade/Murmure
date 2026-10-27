"""Check real native dependencies and decode audio, without downloading a model."""
import importlib.metadata
from pathlib import Path
import subprocess
import sys
import tempfile
import wave


def check():
    import av
    from faster_whisper.audio import decode_audio
    with tempfile.TemporaryDirectory() as directory:
        audio = Path(directory) / "silence.wav"
        with wave.open(str(audio), "wb") as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(16_000)
            output.writeframes(b"\0\0" * 1600)
        decoded = decode_audio(str(audio), sampling_rate=16_000)
        assert len(decoded) == 1600
    print(f"Real runtime import/decode passed: Faster Whisper {importlib.metadata.version('faster-whisper')}, PyAV {av.__version__}. No model loaded.", flush=True)


if __name__ == "__main__":
    if "--child" in sys.argv:
        check()
    else:
        # A hung native import must fail CI/setup checks rather than wait forever.
        subprocess.run([sys.executable, __file__, "--child"], check=True, timeout=30)
