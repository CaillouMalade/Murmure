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
echo "Built $DIST/Murmure-$VERSION-macOS.zip (arm64 + x86_64, macOS 15+)"
