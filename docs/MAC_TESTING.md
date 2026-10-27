# Real Mac verification

These checks have not yet been performed on Arthur's Mac. CI compilation is a separate check.

1. Launch the app from Applications on macOS 15+, approve the development build if macOS asks, and find the icon without a Dock icon appearing.
2. Record microphone audio for a minute. The icon should stay red, stop on the next click and return to its normal appearance. Verify the saved audio externally for this test; the app has no audio player.
3. Deny Microphone access and try recording. Confirm a clear error, no red recording indicator and no submitted job. Restore permission and retry.
4. Test Mac audio alone, and microphone + Mac audio, after granting Screen & System Audio Recording access. For the combined source, speak while playing clearly distinguishable audio. Inspect start alignment, duration, presence of both sources and clipping. Use headphones.
5. Set up a test worker and SSH alias. Confirm first-time unknown hosts are rejected. After verifying the fingerprint in Terminal, use Test SSH connection, send a recording, then fetch the transcript. Check that text is both exported and copyable.
6. Use a recording with two speakers. Enable Label speakers; confirm labels are present, the text is preserved and timestamps can be disabled without losing the labels. Check that missing diarization dependencies fail clearly.
7. Disconnect networking halfway through a long upload. Confirm the original audio remains. Reconnect, check results first, and retry without duplicate inference.
8. Submit a job, close the app or sleep the Mac, then reopen/wake and check results. Confirm the remote process finishes independently. An awake remote computer is required.
9. Configure local Python, disable the remote computer and explicitly choose local processing. Confirm there is no automatic fallback and no idle model process afterwards.
10. Quit/reopen with queued and failed jobs. Confirm their states and original audio are retained. Test quitting during recording and during an upload: the app should ask you to finish those operations first.
11. In Activity Monitor, measure idle CPU, memory and Energy Impact for at least ten minutes with no menu open, then during recording/uploading/local inference. Repeat while disconnected. There should be no repeated SSH child processes or periodic network/disk activity at idle. Record measurements and Mac/OS details; no fixed memory or battery promise is established yet.
