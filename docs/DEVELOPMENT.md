# Development

The app uses Swift Package Manager, AppKit, AVFoundation and ScreenCaptureKit, with no third-party Swift dependencies. The separate Python worker uses standard-library transport and loads Faster Whisper or optional Pyannote only for inference. SSH supplies authentication and host verification. Development commands below require a source checkout, rather than the standalone worker ZIP.

## Local checks

On any supported development computer with Python:

```bash
python -m unittest discover -s worker/tests -v
python -m unittest discover -s scripts/tests -v
python scripts/release.py check
```

On macOS 15+ with Xcode command-line tools:

```bash
swift test
bash scripts/build-app.sh
open dist/Murmure.app
```

The build script compiles Apple Silicon and Intel binaries into one app, checks bundle metadata and worker compatibility, then packages the app and worker separately. It creates no model environment, modifies no SSH settings, and does not Developer ID sign or notarize the app. Run it from a clean checkout for release builds.

The optional worker runtime check needs the separately installed requirements:

```bash
python scripts/check-worker-runtime.py
```

The real-model smoke test is opt-in and can download weights. Use synthetic or public audio:

```bash
python scripts/smoke-worker.py --audio /path/to/synthetic.wav --root /path/to/test-output
```

## CI

`Build and test` runs on changes to main, pull requests, manual dispatch and release-workflow calls. Windows exercises actual OS process lifetime and breakaway refusal. macOS runs worker tests, native Swift tests, synthetic audio/recovery checks, rendering checks and both release builds. Both platforms install the pinned worker dependencies and decode generated silence without downloading models or using accounts. Release automation reuses these same jobs at the exact tag commit.

CI includes a redacted secret scan of the current tree. Release jobs also scan the reachable Git history. Neither is a complete security audit. Actions are pinned to commit hashes; update those deliberately. Fork pull requests receive read-only permissions and never use `pull_request_target`.

## Verification limits

Historical validation is retained in [v0.1](VALIDATION_V1.md), [v0.2](VALIDATION_V2.md), [v0.3](VALIDATION_V3.md) and [v0.4](VALIDATION_V4.md). These records describe the tests performed at those versions; old Actions artifacts may expire. Published release assets use the new workflow instead of temporary artifact links.

Builds and synthetic tests do not establish actual Mac microphone/system capture, global shortcuts, editor accessibility, on-device recognition, real SSH, GPU/diarization quality, provider account behavior or idle energy. Record those separately using [MAC_TESTING.md](MAC_TESTING.md).
