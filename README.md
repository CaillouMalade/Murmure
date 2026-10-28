# Murmure

A small native macOS menu-bar app for recording and dictation, with transcription on your own computer over SSH.

[Download a release](https://github.com/CaillouMalade/Murmure/releases) · [Setup](docs/SETUP.md) · [Usage](docs/USAGE.md) · [Changelog](CHANGELOG.md)

**Experimental prerelease.** Requires macOS 15 or later, on Apple Silicon or Intel. Builds are not Developer ID signed or notarized. Automated checks pass for the earlier milestones, but live Mac capture, permissions, editor insertion and energy use still need testing. This is not yet a recorder to rely on for irreplaceable meetings.

## What it does

- Record your microphone, Mac audio, or both from the menu bar. Save recordings and export transcripts as Markdown with optional timestamps and speaker labels.
- Hold a configurable shortcut to dictate, then insert the finished text at the original cursor. Changed or unsupported fields get a Copy window. Murmure never presses Return or Send.
- Transcribe over key-based SSH by default, with strict host verification. Choose the model and processing computer in Settings. The Mac needs no Python or Whisper model for SSH transcription.
- Optionally use Apple's on-device recognition for quick dictation, or explicitly process recordings locally with a separate worker environment.
- Optionally summarize recordings through your existing Codex CLI or Claude Code installation, using an editable template. Automatic summaries and clipboard copying start off.

The app has no always-loaded model, background polling timer or audio player. Model loading, inference and external CLI installations are separate from the small native app.

## Install

1. Open [Releases](https://github.com/CaillouMalade/Murmure/releases) and choose a published version, including prereleases. Download its `Murmure-<version>-macOS.zip`, matching `Murmure-<version>-worker.zip`, `START_HERE.txt` and `SHA256SUMS`.
2. Unzip the Mac archive and move `Murmure.app` to Applications. If macOS blocks this unsigned build, review it under **System Settings → Privacy & Security** before opening it.
3. Follow [START_HERE.txt](START_HERE.txt): install the worker on the processing computer, verify SSH, choose and prepare a model in **Settings → Setup**. Python 3.11 or 3.12 is recommended for the worker; the Windows setup script uses 3.12.
4. Try a short recording, then dictation in a disposable text field. New installs use **Control + Shift + Space**; upgrades preserve your shortcut. Follow the [Mac checklist](docs/MAC_TESTING.md) before relying on it.

For model choice, GPU requirements, speaker labels, checksum verification and upgrades, see [Setup](docs/SETUP.md). For shortcuts, recovery, Markdown folders and summaries, see [Usage](docs/USAGE.md).

## Where your data goes

Audio and history stay under `~/Library/Application Support/Murmure/Recordings`; Markdown notes go to your chosen folder. Remote transcription sends audio to the SSH computer you configure. Local quick dictation uses on-device speech recognition when available and fails rather than silently using cloud recognition. Optional summaries send the transcript and template through your selected CLI account, whose normal usage and billing apply. Murmure stores no provider credentials.

Recordings are retained until you remove them. Failed jobs preserve their local audio, and no local or cloud fallback starts automatically after an SSH failure. The processing computer must stay awake and reachable. Results are checked on launch, wake, menu interaction or **Check results**; there is no immediate-completion notification guarantee.

## Build and contribute

On macOS 15+ with the Xcode command-line tools and Python installed:

```bash
swift test
python3 -m unittest discover -s worker/tests -v
python3 scripts/release.py check
bash scripts/build-app.sh
open dist/Murmure.app
```

[Development](docs/DEVELOPMENT.md) explains checks and architecture. [Releasing](docs/RELEASING.md) describes version bumps, verified downloads and manual publication. Report bugs through [GitHub issues](https://github.com/CaillouMalade/Murmure/issues); include the version and OS, and remove recordings, transcript content and credentials from logs before sharing.

## Licence

Murmure's source is available under the [MIT licence](LICENSE). Separately installed libraries, CLIs and model weights retain their own licences and access conditions; they are not included in the app or worker ZIP.
