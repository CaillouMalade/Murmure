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

The first native compile caught an entrypoint isolation issue; it was fixed before the passing build. At the v1 milestone no model had been run. No user recording has been captured, SSH has not been configured, and no real Mac UX/energy tests have been performed. Do not claim those passed.

COS returned a read-only review (message 979876ab-a9b2-4d5a-a841-db238d9fc5b0 replying to b8a35455-bc3c-48df-b8d4-8db9284c2fff). Decisions and exact boundaries are recorded in docs/REVIEW_V1.md. V2 commit `6396aa482bfb84fab877bc7aa705a1893e34fb74` passed GitHub run https://github.com/CaillouMalade/Murmure/actions/runs/40592761676 : 18 Windows worker tests (including two actual kill-on-close job-object survival/refusal tests), 16 worker tests on macOS plus two Windows-only skips, six Swift tests, both app architectures and bundle checks. The app directory was 1.2 MiB on disk, excluding Python/models. Native V2 interaction and energy measurements remain unverified.

A separate real worker test passed locally with a public `tiny.en` model, CPU/int8 and synthetic speech encoded to M4A, using streamed input, a real detached worker and result lookup. Sample text is in docs/REVIEW_V1.md. A project-only `.venv` and `.build/model-cache` were created for testing; neither is shipped or committed. Actual installs exposed PyAV 19.0.2/18.1.0 import hangs on Windows/Python 3.13 and the PyAV 19/Faster Whisper metadata API mismatch. Pinning Faster Whisper 1.2.1 + PyAV 16.0.1 passed real import, decode and inference.

Final v2 source `5415f554246756e951d0c21e5cfdfd1dc17141ab` passed https://github.com/CaillouMalade/Murmure/actions/runs/40594377153 : 18 Windows worker tests, 16 macOS worker tests plus two Windows-only skips, six Swift tests, real native runtime import/decode on both OSes, both app architectures and bundle checks. Tag `v0.2.0` targets that exact tested commit. The downloaded final ZIP was inspected for matching versions/architectures and is stored at `dist/final-v0.2.0/Murmure-0.2.0-macOS.zip`; SHA and build link are in docs/VALIDATION_V2.md. It is not Developer ID signed/notarized. Final documentation-only commits follow the tags and do not alter tested app code.

A live localhost SSH attempt was refused by StrictHostKeyChecking because no trusted ED25519 host key is configured; leave that check intact. No Mac-to-G14 SSH session or diarization test has been performed.

## Current next steps

V0.3.0 is in progress at Arthur's request: SSH-first quick dictation with a configurable global shortcut/URL command, a black six-bar menu indicator matching the supplied reference, insertion after transcription (no live words), optional clipboard copy, selectable on-device recognition, Markdown folder selection, and optional Codex/Claude Code summaries using an editable template. The first workflow commit is d58d4f8. Its initial CI caught a Swift test string delimiter error; fixed during continued implementation. No v0.3.0 tag or finished build exists yet. See docs/V0.3_SCOPE.md. Do not redo the completed v1/COS/v2 work below.

The requested v1 → COS review → v2 implementation and GitHub versioning are complete, with automated validation and both immutable milestone tags. Do not redo v1 or ask COS again. Provide the final build/source/review links and attach the final Mac ZIP.

Remaining user-side validation is in docs/MAC_TESTING.md: macOS 15+ UI/recording/permissions/mix, model diarization, real SSH setup and idle energy/memory. These are limitations of the current development build, not claimed successes. Future product changes should follow Arthur's next request; no extra features, publication, signing/notarization, host configuration or routines have been authorized.

## Commands

```text
python -m unittest discover -s worker/tests -v
# With the worker environment installed:
.venv/Scripts/python.exe scripts/check-worker-runtime.py
```

On macOS:

```bash
swift test
bash scripts/build-app.sh
open dist/Murmure.app
```

GitHub workflow: `.github/workflows/ci.yml`, standard `macos-15` and `windows-2025` runners, no model downloads/keys. Artifacts contain a versioned unsigned universal `.app` ZIP. Private-repo runners use the account's Actions allowance. Use `gh run view` for bounded verification reads; no recurring routine was requested. `openbot.await_event` was unavailable on this agent because it has no routines; do not create a routine just to get around that requirement. COS's automatic reply resumed this work normally.
