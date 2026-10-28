# Changelog

Versions use SemVer. All current 0.x builds are experimental. Tags are immutable; published downloads are never replaced in place.

## 0.4.2 — 2026-10-28

- Keep app/worker archives and the first-run guide together in the build artifact so the release workflow can consume them directly.
- Validate actual archive contents before uploading build artifacts, as well as before creating a release draft.
- Preserve v0.4.1 as an unpublished source milestone; no release assets or tags are replaced. App behavior is unchanged from v0.4.0.

## 0.4.1 — 2026-10-28

- Add the MIT licence and public installation, usage, development and release documentation.
- Package matching app/worker downloads with the licence, source metadata and SHA-256 checksums.
- Add a tag-triggered release workflow: both platforms must pass before a draft prerelease is created; publication remains manual.
- Check version agreement, archive contents and source identity before preparing a release.
- Remove personal development notes from the current tree; preserve existing history and milestone tags.
- Keep the v0.4.0 app behavior. Native Mac trials, real SSH, provider inference, diarization quality and energy measurements remain outstanding.

## 0.4.0 — 2026-10-28

- Preserve usable microphone audio after combined-capture failure, disclose dropped samples/partial tracks, keep capture warnings in transcripts and add manual original-track recovery.
- Separate recording and dictation history while retaining older entries' actions.
- Add Copy-only dictation and visible, non-activating recovery for unsupported/changed targets or unconfirmed insertion; verify accessibility text changes and retain secure-field guards.
- Add a Setup tab, model presets/custom paths, explicit remote/local model download/audio checks and a separate worker setup ZIP with a first-download guide.
- Require cached weights for quick dictation, give actionable preparation/CUDA/version failures and expose its processing timeout (one to thirty minutes).
- Default new installs to Control + Shift + Space; preserve existing shortcuts/settings and open Settings when shortcut registration fails.
- Extend worker, settings migration, Markdown warning and native synthetic-audio recovery checks. Real Mac interaction, real SSH, provider inference, diarization quality and energy measurements remain unverified.

## 0.3.0 — 2026-10-28

- Add configurable hold/toggle dictation shortcuts and `murmure://dictation` start/stop/toggle/cancel commands, with SSH selected by default.
- Match the supplied black capsule/six-white-bar reference using native layers, microphone levels while recording, a processing wave and static Reduce Motion behavior. No idle animation or meter.
- Insert only after transcription, preserve the captured field/selection, reject secure/changed targets and keep recovery text available for Copy. Clipboard copying is optional and off by default; no Send/Return action.
- Add an SSH foreground dictation operation that fails fast if the model is busy, plus explicitly selected Apple on-device recognition without cloud fallback.
- Export recording transcripts as Markdown to the chosen folder, preserve older notes and save summaries as separate Markdown files.
- Add Codex/Claude Code executable setup, editable summary templates, optional automatic handoff for new recordings, serial execution and cancellation/manual recovery. Preserve existing CLI login; never put transcripts in shell commands.
- Bound CLI input/output, cancellation and timeout behavior, including blocked pipes and inherited descriptors; reject Claude error envelopes instead of treating them as summaries.
- Add preference-upgrade, CLI-fixture, worker foreground and native rendering checks. Real Mac cursor/shortcut/permission/energy checks and real provider CLI calls remain unverified.

## 0.2.0 — 2026-10-27

- Improve job lifetime, result delivery and recovery without expanding the recording workflow.
- Request Windows process breakaway so remote jobs can outlive SSH, with explicit refusal handling and real OS process-lifetime tests.
- Detect abandoned receiving/queued/running states on demand; do not mislabel live long jobs or overwrite a live runner from a duplicate.
- Mark unread transcripts in the menu bar and job list; open the latest unread result after an explicit check, and show check/error feedback.
- Isolate new local worker files, preserve v1 local paths and metadata, and correctly recover local versus remote uploads.
- Show audio source/duration, activate alerts, avoid empty failed permission attempts, and explain missing worker dependencies in connection tests.
- Stop repeated requests to an unreachable endpoint within one check; keep recording files and all existing SSH verification rules.
- Pin a compatible worker audio runtime after real testing caught newer PyAV import/API problems; add model-free runtime decoding to both CI runners and an opt-in genuine inference smoke test.
- Give the recording symbol an explicit red palette and reuse a single Settings window.

## 0.1.0 — 2026-10-27

- Native macOS 15+ menu-bar app with click-to-record, a red recording indicator and microphone/Mac-audio/combined sources.
- Optional timestamps and speaker labels, persisted recordings, text export and a transcript window with Copy.
- Configurable SSH worker, streamed audio uploads, detached jobs, explicit local CPU fallback and event-driven result checks.
- Key-based SSH with strict host verification, atomic state, idempotent submission and serialized model inference.
- Worker tests, Swift core tests and a universal Mac app build workflow. Native runtime and energy validation remain pending.
