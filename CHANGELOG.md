# Changelog

Versions use SemVer. The first two development milestones are 0.1.0 (v1) and 0.2.0 (reviewed v2); neither is a claim of production readiness.

## 0.2.0 — 2026-10-27

- Address COS's [v1 review](docs/REVIEW_V1.md) without expanding the product scope.
- Request Windows process breakaway so remote jobs can outlive SSH, with explicit refusal handling and real OS process-lifetime tests.
- Detect abandoned receiving/queued/running states on demand; do not mislabel live long jobs or overwrite a live runner from a duplicate.
- Mark unread transcripts in the menu bar and job list; open the latest unread result after an explicit check, and show check/error feedback.
- Isolate new local worker files, preserve v1 local paths and metadata, and correctly recover local versus remote uploads.
- Show audio source/duration, activate alerts, avoid empty failed permission attempts, and explain missing worker dependencies in connection tests.
- Stop repeated requests to an unreachable endpoint within one check; keep recording files and all existing SSH verification rules.

## 0.1.0 — 2026-10-27

- Native macOS 15+ menu-bar app with click-to-record, a red recording indicator and microphone/Mac-audio/combined sources.
- Optional timestamps and speaker labels, persisted recordings, text export and a transcript window with Copy.
- Configurable SSH worker, streamed audio uploads, detached jobs, explicit local CPU fallback and event-driven result checks.
- Key-based SSH with strict host verification, atomic state, idempotent submission and serialized model inference.
- Worker tests, Swift core tests and a universal Mac app build workflow. Native runtime and energy validation remain pending.
