# Changelog

Versions use SemVer. The first two development milestones are 0.1.0 (v1) and 0.2.0 (reviewed v2); neither is a claim of production readiness.

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

- Address COS's [v1 review](docs/REVIEW_V1.md) without expanding the product scope.
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
