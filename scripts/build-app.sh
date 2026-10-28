#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '\r\n' < VERSION)"
DIST="$ROOT/dist"
APP="$DIST/Murmure.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINARIES=()
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx15.0"
    BIN="$(swift build -c release --triple "$ARCH-apple-macosx15.0" --show-bin-path)"
    BINARIES+=("$BIN/Murmure")
done
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Murmure"
cp worker/murmure_worker.py "$APP/Contents/Resources/murmure_worker.py"
cp START_HERE.txt "$APP/Contents/Resources/START_HERE.txt"
python3 - "$ROOT" "$VERSION" <<'PY'
from pathlib import Path
import plistlib
import sys
root, version = Path(sys.argv[1]), sys.argv[2]
with (root / "Resources/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
info["CFBundleShortVersionString"] = version
major, minor, patch = map(int, version.split("."))
info["CFBundleVersion"] = str(major * 1_000_000 + minor * 1_000 + patch)
with (root / "dist/Murmure.app/Contents/Info.plist").open("wb") as handle:
    plistlib.dump(info, handle)
PY
plutil -lint "$APP/Contents/Info.plist"
python3 scripts/check-bundle.py "$APP"
ditto -c -k --keepParent "$APP" "$DIST/Murmure-$VERSION-macOS.zip"
WORKER="$DIST/Murmure-worker"
mkdir -p "$WORKER/worker" "$WORKER/scripts" "$WORKER/docs"
cp worker/murmure_worker.py worker/requirements.txt worker/requirements-diarization.txt "$WORKER/worker/"
cp scripts/setup-worker.ps1 scripts/setup-worker.sh scripts/check-worker-runtime.py "$WORKER/scripts/"
cp START_HERE.txt README.md "$WORKER/"
cp docs/*.md "$WORKER/docs/"
ditto -c -k --keepParent "$WORKER" "$DIST/Murmure-$VERSION-worker.zip"
echo "Built $DIST/Murmure-$VERSION-macOS.zip (arm64 + x86_64, macOS 15+)"
