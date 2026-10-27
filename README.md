# Murmure

A small native macOS menu-bar recorder that sends saved audio to a transcription worker over SSH. The name is provisional.

Click the menu-bar icon to record; it turns red. Click again to stop, save the audio and submit it. Right-click for an audio-source dropdown, timestamps, speaker labels, saved transcripts and Settings. There is no audio player.

Transcripts are kept as JSON and plain text beside the recording, exported as text to `~/Documents/Murmure` (or your chosen folder), and open in a small window with a Copy button. Recordings are retained; this version does not automatically delete them.

## Development build: 0.2.0

Requires macOS 15 or later. The app is native Swift/AppKit with no third-party app dependencies. The optional Python/model environment is separate and can live entirely on the remote computer. No model is loaded by the menu-bar app at idle.

Builds are available as artifacts on the repository's **Actions → Build and test** page after a successful run. Unzip the artifact, then unzip the inner versioned archive and move `Murmure.app` to Applications. These development builds are not Developer ID signed or notarized; macOS may require approving the app under **System Settings → Privacy & Security**. Build locally with Xcode if you prefer.

```bash
swift test
bash scripts/build-app.sh
open dist/Murmure.app
```

The script builds both Apple Silicon and Intel binaries and packages `dist/Murmure-0.2.0-macOS.zip`. It does not install models, modify SSH, sign or notarize the app. V1 is preserved at tag `v0.1.0`; v2 follows COS's [recorded review](docs/REVIEW_V1.md), with a separate `v0.2.0` tag after verification.

## Set up the processing computer

The worker works on Windows, Linux and macOS with Python 3.11 or 3.12 recommended. Use a simple checkout path without spaces for the executable and script paths, such as `C:/Murmure` on Windows or `/home/you/Murmure` on Linux. The data folder may contain spaces.

Install the repository and a separate environment **on the computer that will do transcription**:

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

On Windows, the worker requests `CREATE_BREAKAWAY_FROM_JOB` so a job can survive the SSH session closing. Current OpenSSH supports explicitly requested breakaway, but an administrator/embedding host may forbid it; in that case Murmure fails clearly and keeps the recording. It never changes that policy or installs a scheduled task. Update the remote worker to 0.2.0 as well as the Mac app. The controlled Windows lifetime tests pass; a real Mac-to-G14 SSH/model test remains part of setup.

## Local fallback

To process on your Mac, create a local Python environment with the same worker requirements and put its full Python path in Settings. Select **Process on this Mac…** for a recording. Local inference is CPU/int8, is never started automatically after an SSH failure, and can use noticeable memory and battery. Diarization also requires the local diarization dependencies and model access. The app itself still contains no model runtime. New local worker jobs have their own folder at `~/Library/Application Support/Murmure/LocalWorker`, including a separate audio copy. Existing v1 local jobs remain readable in their old location; no recordings are moved or deleted during the upgrade.

## Permissions and audio

- Microphone capture requests Microphone access only when starting a recording that needs it.
- Mac audio capture uses Apple's ScreenCaptureKit and requires Screen & System Audio Recording permission. It uses an audio output only and saves no video. A permission change may require restarting the app.
- The combined source aligns the two recordings using host-clock start times, then mixes them to a single M4A file. Use headphones for calls to avoid the microphone picking up speaker audio twice.
- No recording starts automatically. The Mac is kept awake only during recording; that assertion ends when recording stops. Models and SSH processes run only when needed.

## Deferred work and recovery

Uploads use bounded-size chunks rather than loading an entire recording into memory. A submitted remote job detaches from SSH, so it can continue if the Mac sleeps, disconnects or quits. One model job runs at a time per worker data folder.

There is no timer checking job status. Results are checked on app launch, Mac wake, opening the options menu and **Check results**. A discovered unread transcript changes the menu-bar icon to a speech bubble and marks its row New. **Check results** opens the latest unread transcript; passive launch/wake checks don't interrupt you with a window. If a worker is unreachable, the app tries it once per check rather than once per pending job. The app intentionally does not keep a live connection or promise an immediate completion notification. The remote computer must itself remain awake to process jobs.

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
