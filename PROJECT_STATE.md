# Murmure project state

## Goal and decisions

Arthur asked for a small, fast Mac menu-bar transcription utility, primarily sending recordings over SSH to another configurable computer (for Arthur, the Windows G14), with local fallback. Audio-source dropdown, optional speaker labels/timestamps, no playback UI, saved transcripts plus a Copy window. No always-loaded model, polling timer, web server, paid API, automatic local fallback, account setup, signing or notarization.

On 2026-10-27 Arthur authorized: “do a first version. then ask @COS its opinion, think, and do a v2 all on github with proper versioning.” Keep v1 and v2 as separate SemVer milestones/tags, record the review and the reasoning behind v2. Repository URL supplied by Arthur redirects to the same private repository under `CaillouMalade/Murmure`; its numeric owner ID is unchanged. Do not change repository visibility/settings.

Local checkout: `C:/Users/Main/OpenBot/Agents/agent-b7c55610-c848-45c1-9124-b0bc224cdc11/Murmure`.

## Implementation

Native Swift/AppKit, Swift Package Manager, macOS 15 minimum, no app package dependencies. AVAudioRecorder for microphone, ScreenCaptureKit audio output for Mac audio, AVFoundation M4A mix on stop. Python stdlib transport worker with optional Faster Whisper and Pyannote Community-1 dependencies on the processing computer. A detached worker per job and a shared model lock; model imports occur only during inference. System SSH config supplies keys/host identity; no secrets in app settings or source.

Results checked on launch, wake and user interaction. V2 marks unread results; an explicit Check results opens the latest unread transcript. New local jobs use a separate LocalWorker folder and retain v1 job paths. V2 requests Windows process breakaway and detects abandoned jobs by OS lock/timestamp on demand. No immediate-result promise. The remote computer must stay awake. Capture and transfer errors keep the source audio. Recordings are never automatically deleted.

## Verified state

V1 source commit `881f1134f835370abaf8f9449215bc7b3bc9077a` passed all 9 worker tests and 4 Swift tests on the GitHub macOS runner, both release architectures, bundle/worker checks and artifact upload. Workflow: https://github.com/CaillouMalade/Murmure/actions/runs/40590697236 . The packaged app directory measured 1.1 MiB on the runner; this is disk size, not measured memory use. The same 9 worker tests passed locally on Windows. Tag `v0.1.0` targets this exact tested source commit; later documentation-only commits record the result.

The first native compile caught an entrypoint isolation issue; it was fixed before the passing build. No model has been downloaded or executed, no user recording captured, no SSH server/model environment configured, and no real Mac UX/energy tests performed. Do not claim those passed.

COS returned a read-only review (message 979876ab-a9b2-4d5a-a841-db238d9fc5b0 replying to b8a35455-bc3c-48df-b8d4-8db9284c2fff). Decisions and exact boundaries are recorded in docs/REVIEW_V1.md. All 18 v2 worker tests passed locally on Windows, including actual kill-on-close job-object survival and refusal tests. A live localhost SSH attempt was refused by StrictHostKeyChecking because no trusted ED25519 host key is configured; leave that check intact. Native v2 tests and universal build are pending.

## Current next steps

1. V1 implementation, automated verification/tag and COS review are complete. V2 focused changes and regression tests are implemented; push and verify the GitHub Windows/macOS workflow.
2. Fix any failures, tag the exact passing v2 source `v0.2.0`, record final evidence and provide the build/source links. The original user request remains active until that is complete. Do not ask COS again or redo v1.

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

GitHub workflow: `.github/workflows/ci.yml`, standard `macos-15` and `windows-2025` runners, no model downloads/keys. Artifacts contain a versioned unsigned universal `.app` ZIP. Private-repo runners use the account's Actions allowance. Use `gh run view` for bounded verification reads; no recurring routine was requested. `openbot.await_event` was unavailable on this agent because it has no routines; do not create a routine just to get around that requirement. COS's automatic reply resumed this work normally.
