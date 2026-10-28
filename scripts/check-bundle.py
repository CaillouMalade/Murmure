"""Check the installable bundle without microphone access or model downloads."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

app = Path(sys.argv[1])
with (app / "Contents/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
assert info["LSUIElement"] is True
assert info["NSMicrophoneUsageDescription"]
assert info["NSScreenCaptureUsageDescription"]
assert info["NSSpeechRecognitionUsageDescription"]
assert any("murmure" in item["CFBundleURLSchemes"] for item in info["CFBundleURLTypes"])
assert (app / "Contents/MacOS/Murmure").is_file()
worker = app / "Contents/Resources/murmure_worker.py"
assert worker.is_file()
assert (app / "Contents/Resources/START_HERE.txt").is_file()
assert (app / "Contents/Resources/LICENSE").is_file()
with tempfile.TemporaryDirectory() as directory:
    request = json.dumps({"op": "probe", "root": directory}).encode() + b"\n"
    result = subprocess.run([sys.executable, str(worker), "rpc"], input=request, capture_output=True, check=True)
    response = json.loads(result.stdout)
    assert response["state"] == "ready", response
    assert response["version"] == info["CFBundleShortVersionString"]
print("Bundle metadata and bundled worker protocol passed.")
