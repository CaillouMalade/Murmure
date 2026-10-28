# Project state

Murmure is an experimental macOS 15+ menu-bar recorder and dictation app. Its scope is native capture, SSH-first transcription, explicit local processing, Markdown export and optional CLI summaries. Keep models outside the app, avoid idle polling and preserve recordings on failure.

## Current work

Version 0.4.2 packages the existing 0.4.0 app behavior for publication: MIT licence, public documentation, a checked release pipeline and matching app/worker downloads. A tag creates a draft prerelease only after both CI jobs pass. Publishing the draft and changing repository visibility are separate manual steps. Existing tags and history stay intact. Version 0.4.1 remains a source milestone: its app build passed, but downloaded-artifact inspection found a release-path mismatch, corrected in 0.4.2 before publication.

## Verification

The latest earlier tested milestone is v0.4.0 at `68af3c1113cfc86457da71f907a2034568f3445e`: 25 Windows worker tests, 23 macOS worker tests (plus two Windows-only skips), 28 Swift tests, native synthetic-audio recovery, runtime decoding and universal app packaging. See [its validation record](docs/VALIDATION_V4.md).

New release results are recorded by the tag's GitHub Actions run, `SHA256SUMS` and `RELEASE.json`; do not infer a passing build from a version number alone. [The live Mac checklist](docs/MAC_TESTING.md) remains outstanding, including actual permissions/capture/editor input, SSH, GPU/diarization, CLI accounts and energy use. Automated native rendering is not a live Mac trial.

## Commands and next step

Use [Development](docs/DEVELOPMENT.md) for build/test commands and [Releasing](docs/RELEASING.md) for the release process. Complete a real Mac trial before treating a build as stable. Do not expand features or alter recording data as part of release preparation.
