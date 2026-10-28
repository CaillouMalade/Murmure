# Using Murmure

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

## Deferred work and recovery

Uploads use bounded-size chunks rather than loading an entire recording into memory. A submitted remote job detaches from SSH, so it can continue if the Mac sleeps, disconnects or quits. One model job runs at a time per worker data folder.

There is no timer checking job status. Results are checked on app launch, Mac wake, opening the options menu and **Check results**. Recordings keep their own recent rows and an Older recordings submenu; dictations have a separate history submenu. All older entries retain their actions. A discovered unread transcript changes the menu-bar icon to a speech bubble and marks its row New. **Check results** opens the latest unread transcript; passive launch/wake checks don't interrupt you with a window. If a worker is unreachable, the app tries it once per check rather than once per pending job. The app intentionally does not keep a live connection or promise an immediate completion notification. The remote computer must itself remain awake to process jobs.

A worker process stopped by a remote reboot is reported as failed/retryable on the next check after a two-minute startup grace, unless a live worker still holds the job's OS lock. Long-running/queued jobs aren't considered failed merely for taking time. There is no periodic heartbeat or automatic restart of an interrupted model job.

Recordings and queue metadata live in `~/Library/Application Support/Murmure/Recordings`. Interrupted uploads are checked before retrying; failed uploads and model errors keep the local audio. If the app is forcibly quit during capture, the separate capture files are retained, but a playable/finalized interrupted recording is not guaranteed.
