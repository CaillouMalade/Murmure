# V1 automated validation

- Tested commit: `881f1134f835370abaf8f9449215bc7b3bc9077a`, tagged `v0.1.0`.
- [Passing GitHub macOS run](https://github.com/CaillouMalade/Murmure/actions/runs/40590697236): 9 worker tests, 4 Swift core tests, arm64 and x86_64 release builds, plist/bundled-worker checks and successful artifact upload.
- Universal architectures confirmed by `lipo -archs`: `x86_64 arm64`.
- App directory disk size from `du -sh`: `1.1M`. This excludes the external Python/model environment and says nothing about resident memory or battery draw.
- [Build download](https://github.com/CaillouMalade/Murmure/actions/runs/40590697236/artifacts/12774172057): GitHub artifact with the versioned development ZIP; availability depends on Actions artifact retention; this was not a published release.
- All 9 worker tests also passed on the Windows development machine with Python 3.13.15; shell-script syntax and Python bytecode checks passed.

The first workflow caught a main-actor entrypoint compile error. Commit `881f113` fixed it and removed a deprecated audio export call before this passing run. The tag is not moved to hide build history.

No actual recording, SSH connection to the processing computer, model inference, speaker quality, Mac UI session, memory measurement or energy test is established by these checks. Those remain the tasks in [MAC_TESTING.md](MAC_TESTING.md). The model integration unit test uses a fake module and performs no download or inference.
