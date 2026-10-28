# Real Mac verification

These checks have not yet been performed on Arthur's Mac. CI compilation is a separate check.

1. Launch the app from Applications on macOS 15+, approve the development build if macOS asks, and find the icon without a Dock icon appearing.
2. Record microphone audio for a minute. The icon should stay red, stop on the next click and return to its normal appearance. Verify the saved audio externally for this test; the app has no audio player.
3. Deny Microphone access and try recording. Confirm a clear error, no red recording indicator and no submitted job. Restore permission and retry.
4. Test Mac audio alone, and microphone + Mac audio, after granting Screen & System Audio Recording access. For the combined source, speak while playing clearly distinguishable audio. Inspect start alignment, duration, presence of both sources and clipping. Use headphones.
5. Set up a test worker and SSH alias. Confirm first-time unknown hosts are rejected. After verifying the fingerprint in Terminal, use Test SSH connection. Test an environment missing dependencies and check the setup feedback. Send a recording, fetch its transcript and check that text is both exported and copyable. Confirm Check results opens a discovered result; passive wake/launch checks should mark it unread without taking focus. Check menu refresh while it is held open and after closing/reopening.
6. Use a recording with two speakers. Enable Label speakers; confirm labels are present, the text is preserved and timestamps can be disabled without losing the labels. Check that missing diarization dependencies fail clearly.
7. Disconnect networking halfway through a long upload. Confirm the original audio remains. Reconnect, check results first, and retry without duplicate inference.
8. On the actual Windows G14 SSH host, submit a job, close the connection/app or sleep the Mac, then reopen/wake and check results. Confirm the remote process finishes independently. An awake remote computer is required. If the host denies breakaway, confirm a clear failure and retained audio. Stop a test worker mid-job, wait past the two-minute startup grace and check that the job becomes retryable rather than remaining queued forever; a legitimately long live job should stay active.
9. Configure local Python, disable the remote computer and explicitly choose local processing. Confirm there is no automatic fallback and no idle model process afterwards. Check new local worker files are under LocalWorker, original recordings stay under Recordings, and v1 local jobs still resolve their original paths.
10. Quit/reopen with queued and failed jobs. Confirm their states and original audio are retained. Test quitting during recording and during an upload: the app should ask you to finish those operations first.
11. In Activity Monitor, measure idle CPU, memory and Energy Impact for at least ten minutes with no menu open, then during recording/uploading/local inference. Repeat while disconnected. There should be no repeated SSH child processes or periodic network/disk activity at idle. Record measurements and Mac/OS details; no fixed memory or battery promise is established yet.

## V0.3 dictation and Markdown workflow

These require a real macOS 15+ session. Native rendering/build checks do not establish live input or permissions.

- Update the SSH worker to v0.3.0. Use a verified host and the worker venv; record a short phrase, release Control + Option + Space and confirm one insertion at the captured cursor. Try hold, toggle, a custom chord and the background URL commands.
- On the first permission request, confirm no recording/insertion occurs until returning to the text field and invoking again. Normal recording should not request Accessibility/Speech Recognition.
- Check a native text field and a browser/editor field, accented French, punctuation and emoji. No words should appear while speaking, no Return/Send should fire, and any selected text should be replaced once.
- Move the cursor, change field/app, edit the target or focus a password box while processing. The old target must not receive text; the saved result must remain available to copy. For a Unicode fallback, inspect the actual field because delivery is not confirmed by accessibility.
- Cancel while listening, starting and processing. Releasing a very quick hold during startup must not leave the mic recording. A cancelled/failed/restarted session must never insert later.
- Verify the black six-bar capsule against the supplied reference in light/dark menu bars and on a notched display. Check the meter, processing wave, Reduce Motion and the return to a static idle icon. Measure idle CPU/wakeups/memory/energy separately.
- Select on-device dictation and a supported language; test with networking unavailable. An unavailable local language must fail clearly without silently using a server. Then switch back to SSH; an unavailable/busy remote must fail without launching local inference.
- Choose a Markdown output folder with spaces and confirm `.md` transcripts, timestamps/speakers, retry after export failure and preservation of an edited existing note. Quick dictation should not create an output-folder note automatically.
- Configure an already signed-in recent Codex/Claude CLI. Check version, manually summarize a synthetic/public transcript and verify the custom template and adjacent `*.summary.md`. Test signed-out/error cases. Turn automatic handoff on for a new recording, off while another summary is queued, and cancel/restart without automatic resending. Original transcripts must remain intact.

