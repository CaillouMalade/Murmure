# Murmure project state

## Goal and decisions

Arthur asked for a small, fast Mac menu-bar transcription utility, primarily sending recordings over SSH to another configurable computer (for Arthur, the Windows G14), with local fallback. Audio-source dropdown, optional speaker labels/timestamps, no playback UI, saved transcripts plus a Copy window. No always-loaded model, polling timer, web server, paid API, automatic local fallback, account setup, signing or notarization.

On 2026-10-27 Arthur authorized: “do a first version. then ask @COS its opinion, think, and do a v2 all on github with proper versioning.” Keep v1 and v2 as separate SemVer milestones/tags, record the review and the reasoning behind v2. Repository URL supplied by Arthur redirects to the same private repository under `CaillouMalade/Murmure`; its numeric owner ID is unchanged. Do not change repository visibility/settings.

Local checkout: `C:/Users/Main/OpenBot/Agents/agent-b7c55610-c848-45c1-9124-b0bc224cdc11/Murmure`.

## Implementation

Native Swift/AppKit, Swift Package Manager, macOS 15 minimum, no app package dependencies. AVAudioRecorder for microphone, ScreenCaptureKit audio output for Mac audio, AVFoundation M4A mix on stop. Python stdlib transport worker with optional Faster Whisper and Pyannote Community-1 dependencies on the processing computer. A detached worker per job and a shared model lock; model imports occur only during inference. System SSH config supplies keys/host identity; no secrets in app settings or source.

Results checked on launch, wake and user interaction. No immediate-result promise. The remote computer must stay awake. Capture and transfer errors keep the source audio. Recordings are never automatically deleted.

## Verified state

V1 source commit `881f1134f835370abaf8f9449215bc7b3bc9077a` passed all 9 worker tests and 4 Swift tests on the GitHub macOS runner, both release architectures, bundle/worker checks and artifact upload. Workflow: https://github.com/CaillouMalade/Murmure/actions/runs/40590697236 . The packaged app directory measured 1.1 MiB on the runner; this is disk size, not measured memory use. The same 9 worker tests passed locally on Windows. Tag `v0.1.0` targets this exact tested source commit; later documentation-only commits record the result.

The first native compile caught an entrypoint isolation issue; it was fixed before the passing build. No model has been downloaded or executed, no user recording captured, no SSH server/model environment configured, and no real Mac UX/energy tests performed. Do not claim those passed.

## Current next steps

1. V1 implementation, automated verification and tag are complete. Send COS (`agent-9041c389-d2e0-4055-9373-00a572fdd91f`) a read-only review request using `openbot.send_message`, with the brief, tag, tests and known limits. End the turn after sending; their reply resumes work.
2. Assess COS's findings, record them with accepted/rejected changes in `docs/REVIEW_V1.md`, implement focused v2 improvements, run checks and tag `v0.2.0`. The original user request is still active until this is complete.

## Commands

```text
python -m unittest discover -s worker/tests -v
```

On macOS:

```bash
swift test
bash scripts/build-app.sh
open dist/Murmure.app
```

GitHub workflow: `.github/workflows/ci.yml`, standard `macos-15` runner, no model downloads/keys. Artifacts contain a versioned unsigned universal `.app` ZIP. Private-repo runners use the account's Actions allowance. Use `gh run view` for bounded status reads, and OpenBot waits when external work is pending; no recurring routine was requested.
