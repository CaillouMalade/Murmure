# Murmure

A small native macOS menu-bar recorder and dictation utility. Transcription runs over SSH by default; the name is provisional.

Click the menu-bar icon to record; it turns red. Click again to stop, save the audio and submit it. Right-click for an audio-source dropdown, timestamps, speaker labels, saved transcripts and Settings. There is no audio player.

Recording transcripts are saved as JSON and Markdown beside the audio, exported as `.md` to `~/Documents/Murmure` or your chosen folder, and open in a small window with Copy. Optional Codex/Claude Code summaries are separate Markdown files beside the exported transcript. Existing notes are never overwritten. Recordings are retained; this version does not automatically delete them.

## Development build: 0.4.0

Requires macOS 15 or later. The app is native Swift/AppKit with no third-party app dependencies. The optional Python/model environment is separate and can live entirely on the remote computer. No model is loaded by the menu-bar app at idle.

Builds are available as artifacts on the repository's **Actions → Build and test** page after a successful run. Unzip the artifact, then unzip the inner versioned archive and move `Murmure.app` to Applications. These development builds are not Developer ID signed or notarized; macOS may require approving the app under **System Settings → Privacy & Security**. Build locally with Xcode if you prefer.

```bash
swift test
bash scripts/build-app.sh
open dist/Murmure.app
```

The script builds both Apple Silicon and Intel binaries and packages `dist/Murmure-0.4.0-macOS.zip` plus a separate `dist/Murmure-0.4.0-worker.zip`. It does not install models, modify SSH, sign or notarize the app. [START_HERE.txt](START_HERE.txt) gives the first-download setup order. Earlier tags preserve the prior builds, including v0.3.0 for comparison. The [council review and v0.4 decisions](docs/REVIEW_V3.md) record what changed and what was deferred.

## First run and model choice

The Mac needs **no Python or Whisper install when using SSH**. Install the worker environment and chosen model on the processing computer instead. A fresh app opens **Settings → Setup**: install the worker, verify SSH, select a model, choose **Download & check SSH model**, wait for its audio check, then Save. The separate worker ZIP avoids needing a Git checkout on the server. Extract its `Murmure-worker` folder to a permanent simple path, such as `C:/Murmure`.

The Setup page offers editable model presets: `tiny`, `base`, `small` (default), `medium`, `large-v3` and `turbo`. These are multilingual; `.en` variants are English-only. Smaller models generally favor speed and larger models use more resources; model names are options, not a measured accuracy/latency promise. An existing CTranslate2 model directory on the processing computer is also accepted. Short French/English dictations may benefit from explicitly setting `fr` or `en`.

Model preparation explicitly downloads missing weights on the chosen computer, loads the selected CPU/GPU implementation and transcribes generated silence to catch audio/GPU runtime errors before the first recording. It takes the same worker engine lock and refuses promptly while another job is active. The process exits afterwards; models are never kept loaded at idle. Select CPU if CUDA/cuDNN is not configured. If Label speakers is enabled, preparation also checks access to its optional Community-1 pipeline, but does not establish diarization quality.

Model checks can be cancelled and time out after 30 minutes; downloaded cache files remain. Quick dictation uses cached model files and reports a setup error instead of silently starting a first-use download. Deferred long recordings retain their existing first-use download behavior. The app and worker should both be v0.4.0 for the new setup operation.

## Set up the processing computer

The worker works on Windows, Linux and macOS with Python 3.11 or 3.12 recommended. Use a simple checkout path without spaces for the executable and script paths, such as `C:/Murmure` on Windows or `/home/you/Murmure` on Linux. The data folder may contain spaces.

Install the repository and a separate environment **on the computer that will do transcription**:

The worker ZIP or checkout includes `scripts/setup-worker.ps1` (Windows, Python 3.12) and `scripts/setup-worker.sh` (Mac/Linux). Run the appropriate script from that folder to create its `.venv`, install pinned worker requirements, check real runtime decoding and print the Settings paths. It does not configure SSH or download model weights. If script execution is restricted, use the individual commands below rather than changing your system policy.

```bash
python -m venv .venv
# Linux/macOS:
.venv/bin/python -m pip install -r worker/requirements.txt
# Windows instead:
.venv/Scripts/python.exe -m pip install -r worker/requirements.txt
```

The worker requirements pin Faster Whisper 1.2.1 and PyAV 16.0.1. Newer PyAV 19 removed an audio-opening argument that this Faster Whisper version uses; the runtime check below catches native import/decode failures without downloading a model:

```bash
# Linux/macOS:
.venv/bin/python scripts/check-worker-runtime.py
# Windows instead:
.venv/Scripts/python.exe scripts/check-worker-runtime.py
```

Faster Whisper downloads the selected model the first time it runs. The default is `small`. Auto selects CUDA when CTranslate2 reports a CUDA device, otherwise CPU/int8; device discovery alone does not prove that the required runtime libraries are installed. An incomplete GPU setup reports a job error. A model directory may be used instead of a model name to use previously downloaded weights. NVIDIA acceleration needs the compatible CUDA/cuDNN libraries described in the [Faster Whisper documentation](https://github.com/SYSTRAN/faster-whisper#gpu).

For speaker labels, also install `worker/requirements-diarization.txt`, install FFmpeg for Pyannote's audio decoding, accept the [Community-1 model conditions](https://huggingface.co/pyannote/speaker-diarization-community-1), and authenticate Hugging Face **on the processing computer** with its CLI. Alternatively, set `MURMURE_HF_TOKEN_FILE` to a private file outside this repository containing your token; the worker inherits that environment variable. Never paste a token into Murmure Settings or commit it. The worker uses the open-source Community-1 pipeline, not a paid service. Diarization labels speakers; it does not identify people by name, and overlapping speech may be ambiguous.

On your Mac, configure SSH key authentication and a known host using your normal SSH setup. For example, in `~/.ssh/config`:

```sshconfig
Host transcription
    HostName your-processing-computer
    User your-username
    IdentityFile ~/.ssh/id_ed25519
```

Connect in Terminal once and verify the host fingerprint yourself. Murmure uses `BatchMode=yes` and `StrictHostKeyChecking=yes`; it never asks for or stores SSH passwords, bypasses host checks, installs an SSH server, or opens network ports.

In Murmure Settings, enter your SSH alias, the remote Python executable, and the full remote worker script path. Windows example: `C:/Murmure/.venv/Scripts/python.exe` and `C:/Murmure/worker/murmure_worker.py`. Linux example: `/home/you/Murmure/.venv/bin/python` and `/home/you/Murmure/worker/murmure_worker.py`. Keep these two paths free of spaces and shell punctuation. Use an explicit venv path, rather than a Windows Store `python3` alias. **Test SSH connection** distinguishes missing worker dependencies from a successful connection, but it does not load or verify model weights. Then choose **Save**.

On Windows, deferred recording jobs request `CREATE_BREAKAWAY_FROM_JOB` so they can survive the SSH session closing. An administrator/embedding host may forbid it; in that case Murmure fails clearly and keeps the recording. It never changes that policy or installs a scheduled task. Update the remote worker to **0.4.0** as well as the Mac app: model preparation uses a new operation, and quick dictation now requires cached weights. Controlled Windows lifetime tests pass; a real Mac-to-G14 SSH/model test remains part of setup.

## Local fallback

To process on your Mac, create a local Python environment with the same worker requirements and put its full Python path in Settings. Select **Process on this Mac…** for a recording. Local inference is CPU/int8, is never started automatically after an SSH failure, and can use noticeable memory and battery. Diarization also requires the local diarization dependencies and model access. The app itself still contains no model runtime. New local worker jobs have their own folder at `~/Library/Application Support/Murmure/LocalWorker`, including a separate audio copy. Existing v1 local jobs remain readable in their old location; no recordings are moved or deleted during the upgrade.

## Quick dictation

On new installations the default shortcut is **Control + Shift + Space** (upgrades preserve the existing shortcut), held while speaking. Release it to finish. Under **Settings → Dictation**, record another key combination, choose hold or toggle, and select **SSH** (default) or **On this Mac**. A right-click menu action can also start/finish/cancel dictation. The menu bar becomes a small black capsule with six white bars: microphone levels while listening, a gentle travelling wave while processing. Reduce Motion uses static bars. There is no live text preview and no animation or meter timer at idle.

After processing, Murmure replaces the original text selection or inserts at the captured cursor. It does not press Return or Send. Accessibility permission is needed for this action; normal recording does not need it. The original app, field, selection and readable text must remain unchanged. A password field rejects dictation before recording. Unsupported/unreadable editors can still be dictated into using a Copy window. If the field or cursor changes while processing, nothing is inserted there and a recovery window appears. Accessibility edits are read back against the expected text; Unicode-key delivery remains unconfirmed. The recovery window warns you to inspect the original field before copying twice and opens without activating Murmure. Turn off cursor insertion in Dictation settings for an explicit Copy-only workflow without Accessibility access.

The first permission request may change focus; Murmure asks you to return to your field and invoke the shortcut again before recording. **Also copy finished dictation to the clipboard** is a separate option, off by default. Otherwise the clipboard is untouched. Dictation results/audio remain in internal history for recovery; utterances do not automatically create notes in the output folder or invoke a CLI summary. A failed/interrupted dictation can be transcribed manually from history; it will never insert later into a stale target after restart.

SSH dictation uploads after stopping, waits on that one connection for the result, and closes it. Its processing timeout defaults to three minutes and is adjustable from one to thirty minutes under Dictation; this is not a recording-duration limit. A missing cached model fails with a Setup instruction, rather than downloading during dictation. It fails promptly when another job holds the worker's model lock. There is no silent local fallback or model kept loaded between utterances. Cold model loading and SSH startup affect response time; choose a smaller model or a supported GPU for faster remote results. Local dictation uses Apple's on-device speech recognition for the selected language, without installing Whisper. If the language/model is unavailable locally, it reports an error instead of sending audio to Apple's servers. Speech Recognition permission is requested only for that local choice.

The command interface uses the registered URL scheme. From a Mac terminal or shortcut, use background opening to keep the target app focused:

```bash
open -g 'murmure://dictation/start'
open -g 'murmure://dictation/stop'
open -g 'murmure://dictation/toggle'
open -g 'murmure://dictation/cancel'
```

## Markdown and agent summaries

Choose the destination under **Settings → Recordings → Markdown folder**. Each recording gets a dated, uniquely named `.md` note, with optional timestamps and speaker labels. The internal transcript survives an export failure; **Export Markdown** can retry. Older text transcripts remain readable and can be exported as Markdown. Audio stays in Application Support, not in the selected notes folder.

Under **Settings → Summaries**, select Codex CLI or Claude Code, choose its executable and edit the output template. Use an existing installation signed in through its normal terminal flow. `command -v codex` or `command -v claude` identifies the path on the Mac; choose that file in Settings. **Check CLI version** verifies only the executable, not account login or provider access. Recent CLI versions supporting the documented flags are required.

**Automatically summarize new recordings** starts off. You can first use **Summarize with …** on one completed recording. When enabled, a new recording remembers the provider/template at capture time and is summarized after transcription. Turning the option off prevents pending automatic handoffs. One summary command runs at a time, and a queued/running summary can be cancelled from its history menu. Interrupted jobs require a manual retry and are never silently resent. Provider use follows the selected CLI account's normal usage and billing; Murmure stores no provider credentials.

The app sends the transcript and template through stdin without a shell and captures the final Markdown in a separate `*.summary.md` file; the original transcript is preserved. The command uses a fresh temporary working directory, with Codex in read-only mode and shell/web/apps/plugins/user hooks disabled, or Claude in safe print mode with tools disabled. Existing login and managed policies still apply. Errors and missing login appear on the job instead of becoming a fake summary. No provider inference was run during development: executable fixtures verify argument/stdin handling and Markdown/error parsing.

## Permissions and audio

- Microphone capture requests Microphone access only when starting a recording that needs it.
- Mac audio capture uses Apple's ScreenCaptureKit and requires Screen & System Audio Recording permission. It uses an audio output only and saves no video. A permission change may require restarting the app.
- The combined source aligns the two recordings using host-clock start times, then mixes them to a single M4A file. Transient writer backpressure drops only the affected system samples and records a warning. If system finalization or mixing fails, a valid microphone track is finalized instead with an explicit warning retained in history and exported Markdown. Original capture tracks are preserved. Failed/interrupted history entries with readable capture tracks also offer explicit Recover actions; recovery does not submit or insert anything. Use headphones for calls to avoid the microphone picking up speaker audio twice.
- No recording starts automatically. The Mac is kept awake only during recording; that assertion ends when recording stops. Models and SSH processes run only when needed.

## Deferred work and recovery

Uploads use bounded-size chunks rather than loading an entire recording into memory. A submitted remote job detaches from SSH, so it can continue if the Mac sleeps, disconnects or quits. One model job runs at a time per worker data folder.

There is no timer checking job status. Results are checked on app launch, Mac wake, opening the options menu and **Check results**. Recordings keep their own recent rows and an Older recordings submenu; dictations have a separate history submenu. All older entries retain their actions. A discovered unread transcript changes the menu-bar icon to a speech bubble and marks its row New. **Check results** opens the latest unread transcript; passive launch/wake checks don't interrupt you with a window. If a worker is unreachable, the app tries it once per check rather than once per pending job. The app intentionally does not keep a live connection or promise an immediate completion notification. The remote computer must itself remain awake to process jobs.

A worker process stopped by a remote reboot is reported as failed/retryable on the next check after a two-minute startup grace, unless a live worker still holds the job's OS lock. Long-running/queued jobs aren't considered failed merely for taking time. There is no periodic heartbeat or automatic restart of an interrupted model job.

Recordings and queue metadata live in `~/Library/Application Support/Murmure/Recordings`. Interrupted uploads are checked before retrying; failed uploads and model errors keep the local audio. If the app is forcibly quit during capture, the separate capture files are retained, but a playable/finalized interrupted recording is not guaranteed.

## Verification and limits

```bash
python -m unittest discover -s worker/tests -v
swift test
bash scripts/build-app.sh
```

CI tests the worker protocol without models or credentials, verifies actual Windows process lifetime in OS job objects, runs native core/upgrade tests, builds both Mac architectures, checks the bundle and uploads an installable ZIP. The Windows lifetime test kills a session-like parent and checks that the worker child survives; it also tests a host that denies breakaway. It does not authenticate over SSH. Those checks do not establish microphone/system-audio behavior, model quality, SSH access to your computer, or idle memory/battery numbers. Use the [Mac verification checklist](docs/MAC_TESTING.md) before treating it as a daily recorder. Development is taking place on Windows; native interaction and energy measurements need a real Mac.

A separate opt-in real-model test passed on Windows with synthetic English speech encoded to M4A, the `tiny.en` model and CPU/int8. It submitted through the worker protocol, waited for the actual detached process and fetched the transcript; no inference modules were faked. This establishes that basic worker path, not speaker-label accuracy or real Mac recording. To repeat with synthetic audio of your own, use the worker venv to run `scripts/smoke-worker.py --audio /path/to/synthetic.wav --root /path/to/test-output`. It downloads a public model on first use. CI's runtime checks install the dependencies and decode generated silence; CI does not download model weights.

See [PROJECT_STATE.md](PROJECT_STATE.md), [CHANGELOG.md](CHANGELOG.md), and the [worker protocol](docs/PROTOCOL.md).

The [v0.3.0 validation record](docs/VALIDATION_V3.md) links the passing build, inspected download and remaining real-Mac checks, including the native capsule preview.

The [v0.4.0 validation record](docs/VALIDATION_V4.md) records the exact passing source, synthetic audio recovery/mixing, real offline model checks and inspected app/worker ZIPs. Live native interaction, server setup and energy measurements remain separate from these automated checks.
