# Setup

Download the matching app and worker from [Releases](https://github.com/CaillouMalade/Murmure/releases). Start with [START_HERE.txt](../START_HERE.txt) for the short checklist.

## First run and model choice

The Mac needs **no Python or Whisper install when using SSH**. Install the worker environment and chosen model on the processing computer instead. A fresh app opens **Settings → Setup**: install the worker, verify SSH, select a model, choose **Download & check SSH model**, wait for its audio check, then Save. The separate worker ZIP avoids needing a Git checkout on the server. Extract its `Murmure-worker` folder to a permanent simple path, such as `C:/Murmure`.

The Setup page offers editable model presets: `tiny`, `base`, `small` (default), `medium`, `large-v3` and `turbo`. These are multilingual; `.en` variants are English-only. Smaller models generally favor speed and larger models use more resources; model names are options, not a measured accuracy/latency promise. An existing CTranslate2 model directory on the processing computer is also accepted. Short French/English dictations may benefit from explicitly setting `fr` or `en`.

Model preparation explicitly downloads missing weights on the chosen computer, loads the selected CPU/GPU implementation and transcribes generated silence to catch audio/GPU runtime errors before the first recording. It takes the same worker engine lock and refuses promptly while another job is active. The process exits afterwards; models are never kept loaded at idle. Select CPU if CUDA/cuDNN is not configured. If Label speakers is enabled, preparation also checks access to its optional Community-1 pipeline, but does not establish diarization quality.

Model checks can be cancelled and time out after 30 minutes; downloaded cache files remain. Quick dictation uses cached model files and reports a setup error instead of silently starting a first-use download. Deferred long recordings retain their existing first-use download behavior. Use the app and worker from the same release; both must be v0.4.0 or later for the new setup operation.

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

On Windows, deferred recording jobs request `CREATE_BREAKAWAY_FROM_JOB` so they can survive the SSH session closing. An administrator/embedding host may forbid it; in that case Murmure fails clearly and keeps the recording. It never changes that policy or installs a scheduled task. Update the remote worker as well as the Mac app: model preparation uses a new operation, and quick dictation now requires cached weights. Controlled Windows lifetime tests pass; a real Mac-to-server SSH/model test remains part of setup.

## Local fallback

To process on your Mac, create a local Python environment with the same worker requirements and put its full Python path in Settings. Select **Process on this Mac…** for a recording. Local inference is CPU/int8, is never started automatically after an SSH failure, and can use noticeable memory and battery. Diarization also requires the local diarization dependencies and model access. The app itself still contains no model runtime. New local worker jobs have their own folder at `~/Library/Application Support/Murmure/LocalWorker`, including a separate audio copy. Existing v1 local jobs remain readable in their old location; no recordings are moved or deleted during the upgrade.

## Permissions and audio

- Microphone capture requests Microphone access only when starting a recording that needs it.
- Mac audio capture uses Apple's ScreenCaptureKit and requires Screen & System Audio Recording permission. It uses an audio output only and saves no video. A permission change may require restarting the app.
- The combined source aligns the two recordings using host-clock start times, then mixes them to a single M4A file. Transient writer backpressure drops only the affected system samples and records a warning. If system finalization or mixing fails, a valid microphone track is finalized instead with an explicit warning retained in history and exported Markdown. Original capture tracks are preserved. Failed/interrupted history entries with readable capture tracks also offer explicit Recover actions; recovery does not submit or insert anything. Use headphones for calls to avoid the microphone picking up speaker audio twice.
- No recording starts automatically. The Mac is kept awake only during recording; that assertion ends when recording stops. Models and SSH processes run only when needed.

## Check your downloads

Download `SHA256SUMS` beside the two ZIPs and `START_HERE.txt`. From that folder on macOS:

```bash
shasum -a 256 -c SHA256SUMS
```

On Windows, run `Get-FileHash -Algorithm SHA256` for each downloaded file and compare it with the matching entry in `SHA256SUMS`. `RELEASE.json` records the exact source commit, version, sizes and hashes. Checksums detect a corrupted or mismatched download; these builds are still not Developer ID signed or notarized.

## Upgrading

Quit Murmure, replace the app in Applications and update the server's worker from the matching release. Keep the existing worker data directory and Python environment; rerun its setup script if the requirements changed. Never replace the data directory with an empty one. Settings and recording history remain in Application Support. Back up that folder before trying an older version.
