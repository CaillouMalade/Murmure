# V0.3 council review and v0.4 decisions

Arthur requested the local `ask-the-council` skill before trying v0.3.0. The target was immutable source `48e1ae4a0b0f638d226448453246202e21ce00d2`. Four identical requests supplied line-numbered tagged source, tests and the validation record. Opinions were static; no reviewer ran the app on a Mac.

Opus 5.5 and Grok 4.7 inspected source and supported a controlled first Mac trial. Opus prioritized partial audio recovery before important meetings; Grok preferred observing native behavior before changing it. GPT-6.1 Sol returned a brief-only assessment because it could not read the attachments without commands. Gemini 4 Argon was blocked by its file-access policy and could assess only the architectural brief. These are two source reviews, not four independently verified audits. No request was repeated or file restriction bypassed.

## Arthur's subsequent decisions

Arthur confirmed that the G14 is an always-awake server, approved separate histories, and authorized implementing relevant feedback plus anticipating first-download setup problems. No server power-policy change is needed. He asked how model selection/installation works and wants to compare the original and updated versions.

## Implemented for v0.4.0

- Recover a usable microphone track when system audio or mixing fails, retain originals, and keep explicit capture warnings in history, the transcript window and Markdown. A transient real-time writer backpressure event no longer poisons the entire recording. Add manual recovery for readable original tracks from older failed/interrupted sessions; recovery neither submits nor inserts text.
- Keep recording rows and a separate dictation history. Older recordings retain their Open/Export/Summarize/Retry actions.
- Continue unsupported/unreadable-editor dictation as Copy-only. Preserve secure-field rejection and changed-target checks. Read back accessibility edits before marking insertion confirmed. Show a non-activating Copy/recovery window for changed targets or unconfirmed delivery, warning against duplicates. Add an explicit Copy-only setting, without Accessibility permission.
- Use Control + Shift + Space for new installs, preserving existing saved shortcuts. Explain the previous Control + Option + Space input-language conflict in Settings. Open Settings if shortcut registration fails.
- Add a focused Setup tab, model presets/custom directory, server/local installation instructions and explicit Download & check model actions. Preparation loads weights and tests generated-silence transcription, including the selected GPU runtime; it exits afterwards. Optional diarization preparation checks pipeline access, not speaker accuracy. No SSH policy or account configuration is changed.
- Keep quick dictation model lookup cache-only to avoid surprise downloads during the first utterance. Make its post-recording processing timeout configurable from one to thirty minutes, default three. Provide actionable missing-model/CUDA/worker-version errors. Keep deferred jobs and strict SSH unchanged.
- Package a separate worker ZIP with platform setup scripts and a short first-download guide. These install dependencies only when the user runs them, with no model download, SSH installation, account change or global policy bypass.

## Kept or deferred

The G14 remains awake under its existing server configuration. No warm daemon, idle polling, playback UI, live text, silent local/cloud fallback, signing/notarization or automatic summaries were added. Cold model loading still affects each remote utterance; measure it on the selected G14 model before changing that architecture. First-Mac capture, permissions, shortcut delivery, target-editor behavior, real SSH and energy measurements remain necessary. Summary CLI account calls and diarization quality remain outside automated proof.

The combined-capture failure, menu limit and unconfirmed-insertion behavior were checked against the tagged source by Murmure before implementation. A correction to the reviewers' wording: the old `resultNeedsCopy` callback updated only menu feedback; it did not already open a Copy window.
