# V2 automated validation

V2 includes the [recorded changes](../CHANGELOG.md#020--2026-10-27). The earlier milestone remains at `v0.1.0`; no tag was rewritten.

- Tested v2 source: `5415f554246756e951d0c21e5cfdfd1dc17141ab`, tagged `v0.2.0`.
- [Final passing workflow](https://github.com/CaillouMalade/Murmure/actions/runs/40594377153): all 18 Windows worker tests passed, including actual Windows job-object survival and refusal. On macOS, 16 worker tests passed and the two Windows-only tests were skipped. All six Swift core/upgrade tests passed.
- Both Windows and macOS installed the pinned runtime and passed a real native import/audio-decode check: Faster Whisper 1.2.1 and PyAV 16.0.1. That check loads no model weights and uses generated silence.
- Both release app architectures built; `lipo` confirmed `x86_64 arm64`. Bundle metadata and the bundled worker protocol passed. App directory disk size was `1.2M`, excluding the external Python/model environment; resident memory and power were not measured.
- [Mac development build](https://github.com/CaillouMalade/Murmure/actions/runs/40594377153/artifacts/12774299583). The inner archive is `Murmure-0.2.0-macOS.zip`, 392,440 bytes. The downloaded archive was re-read on the development machine and checked for the correct bundle/worker versions, menu-bar setting, macOS 15 minimum and both Mach-O architectures.
- SHA-256 of that inner ZIP: `69467ae7aecd8e7d4f3ed176bd02199164f6b5f8dea4db30746e59bdb803ce81`.

## Actual inference check

A project-only Windows Python 3.13 environment submitted synthetic English speech encoded to AAC/M4A to the real streamed worker request handler. The real detached child loaded the public `tiny.en` model on CPU/int8 and completed; the result was fetched through a separate worker status invocation. The output was:

> Murmur keeps the recording safe. The remote computer transcribes it while the Mac can sleep.

The fixture was generated with Windows speech synthesis; it was not a microphone recording. No inference module was mocked, no private recording was used and no credential or paid API was used. This one success is not a model-quality benchmark. Repeat with `scripts/smoke-worker.py` and synthetic audio; it is deliberately opt-in because it downloads model weights.

This check caught native import hangs with PyAV 19.0.2/18.1.0 on this machine, as well as the independently confirmed PyAV 19/Faster Whisper API incompatibility. PyAV 16.0.1 passed import, decode and inference; requirements now pin the verified pair. Local venv unit tests and `pip check` also passed.

## Remaining real-world checks

The development app is not Developer ID signed or notarized. No native Mac UI session, real microphone/system recording, audio mix/alignment, speaker diarization, memory/energy measurement or authenticated Mac-to-server SSH test has been performed. A localhost SSH preflight correctly refused an unknown host key; no SSH service/configuration was changed to make it pass. Use [MAC_TESTING.md](MAC_TESTING.md) during setup. The remote worker environment and SSH trust still need configuring by the user.
