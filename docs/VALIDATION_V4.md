# V0.4.0 validation

Tag `v0.4.0` targets exact tested source `68af3c1113cfc86457da71f907a2034568f3445e`. Both jobs passed in [GitHub run 40647711856](https://github.com/CaillouMalade/Murmure/actions/runs/40647711856). Earlier tags, including v0.3.0, are preserved. Later documentation-only commits record this evidence; no GitHub release was published.

## Automated checks

- All 25 Windows worker tests passed, including actual OS process lifetime/refusal, model-preparation protocol, busy-engine rejection, cached-only dictation and sanitized missing-model errors.
- On macOS, 23 worker tests passed and two Windows-only lifetime tests were skipped.
- All 28 Swift tests passed: six existing core tests, fourteen workflow tests, four new native audio/selection tests, two native settings/recovery-window checks and two indicator tests.
- Actual AVFoundation synthetic AAC tracks were exported/mixed with a known start offset. A missing system track recovered readable microphone audio with a warning and retained the original. Invalid audio failed without creating a finalized recording. These tests do not access recording devices.
- Migration tests preserve v0.3 preferences/custom shortcuts and add the new defaults. Capture warnings survive repository persistence and Markdown output. Invalid model/language settings fail before recording. UTF-16 selection replacement is checked with accented text and emoji.
- Both CI platforms installed the pinned requirements and passed actual native imports and generated-silence decoding, without model downloads.
- Both arm64 and x86_64 release binaries were built and bundled as a universal macOS 15+ app. Bundle/worker metadata, guide resources and permissions checks passed.
- The four Settings tabs, Setup's scrolled model/local section, six-bar indicator and Copy recovery window rendered to native PNGs. The previews were downloaded and inspected. A warning that was hard to see in an offscreen preview received an opaque native banner; the final preview clearly shows it. The layout check uses measured font height instead of assuming a particular line count.
- PowerShell setup-script parsing, Bash syntax for setup/build scripts and Python compilation passed locally. Setup scripts were not used to install software or change Arthur's server.

## Actual CPU model checks

Using the existing ignored project environment/cache on Windows, a real `prepare` RPC with cached public `tiny.en`, CPU/int8 and generated silence returned `ready`, version `0.4.0`, model `tiny.en`, device `cpu`. `HF_HUB_OFFLINE=1` ensured that check required no network/download.

A separate real foreground dictation RPC with synthetic English speech passed, also offline with the cached model, and returned:

> Murmur keeps the recording safe. The remote computer transcribes it while the Mac can sleep.

Job `98e2b454-7a8a-464f-a60f-03d9876b5d67` is under ignored `.build/v4-dictation-smoke`. No private recording, provider call, key, new model download, SSH setup or account change was used. The model/venv are not shipped. This proves local worker/RPC inference, not Mac-to-G14 transport or CUDA.

## Inspected downloads

Artifacts from the final passing run were downloaded to `dist/verified-v0.4.0` and inspected, rather than reusing an earlier candidate with the same version number.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `Murmure-0.4.0-macOS.zip` | 751803 | `c47a6fc9ef4bbdfbaa96d0ac98a3dbb4b98a9fd7861ddcb55d7a3097ed58435a` |
| `Murmure-0.4.0-worker.zip` | 38499 | `fca921e2fb2860f4b0470c48300cba21a9a989e2d28522626ce8882a0ed8f7a7` |

The app reports version `0.4.0`, build `4000`, has both Mach-O architectures and executable permission bits, and includes the byte-matching worker and first-run guide. The app directory measured 2.3 MiB on the runner; this is disk size, not idle RAM/energy. The worker ZIP's scripts, requirements and source match the tested checkout and contain no model/venv.

The preserved v0.3.0 ZIP was rehashed and still matches `4f000a225dbc4bb599f077a4f63a08e8560b96581bd8f4c3ca880b971bd50286` for comparison. Quit one version before trying the other; they share preferences/history. See [MAC_TESTING.md](MAC_TESTING.md) for downgrade/backup notes.

## Still unverified

Development runs on Windows. Live Mac capture/permissions, actual shortcut press/release, target-editor insertion and non-activation behavior, Apple recognition, real Mac-to-G14 SSH, GPU inference, diarization quality, actual provider CLI accounts and idle memory/energy still require native user trials. The G14 already stays awake as a server; no power policy was changed. These remain unsigned, non-notarized development builds. [START_HERE.txt](../START_HERE.txt) covers the one-time worker/model/SSH setup; it has not been performed for Arthur automatically.
