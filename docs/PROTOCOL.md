# Worker protocol, schema 1

The app launches either system SSH or a configured local Python executable. There is no listening HTTP service. The remote command is `<python> -u <worker.py> rpc`; the SSH alias and the two executable/script tokens are validated before any remote shell sees them. Remote paths containing whitespace or shell punctuation are deliberately unsupported in the first version.

Each invocation receives one UTF-8 JSON header terminated by a newline (at most 16 KiB). `submit` and v0.3 `transcribe` are followed by exactly `bytes` bytes of M4A audio, transferred in chunks. The response is one JSON object on stdout. Deferred inference logs go to the job folder; foreground inference logs go to stderr, preserving the JSON response stream. This is an internal protocol, not an internet-facing service.

```json
{"op":"submit","root":"~/.murmure","id":"e6d87382-6176-43c0-a33a-c44b64a8be4d","bytes":12345,"options":{"model":"small","language":"","device":"auto","diarization":false,"timestamps":true}}
```

`probe` returns worker version, `protocolVersion: 1`, and whether Faster Whisper/Pyannote are installed, without importing the model runtime. `status` takes `root` and `id` and returns `missing`, `receiving`, `queued`, `running`, `completed` or `failed`. Failed responses contain `error`; completed responses contain a `transcript` with `language` and `segments` (`start`, `end`, `text`, optional `speaker`). A protocol rejection returns `state: error`. V1 responses without `protocolVersion` remain compatible, but lack the v2 lifecycle fixes.

Submission uses UUID directories, an OS file lock, a partial audio file, atomic JSON replacement and a detached subprocess. Duplicate submission of a queued/running/completed job consumes the input without launching another model process. A failed submission can be retried with the same ID. A separate lock serializes inference across jobs. No model import happens in the submit/status processes.

Status includes `updatedAt` (Unix seconds). A receiving/queued/running status older than 120 seconds is considered abandoned only if its corresponding submission/run OS lock can be acquired. A long job continues to hold its run lock while waiting for the shared inference lock. Abandoned work becomes failed/retryable; it isn't restarted by a read. V1 status files fall back to file modification time.

Windows launches explicitly request `CREATE_BREAKAWAY_FROM_JOB`; refusal reports failure without retrying a less independent process. New local worker roots are distinct from app recording roots. Optional app metadata tracks that root and transcript read state; old metadata without those fields remains readable.

The app retains the connection settings used by each job so changing Settings does not silently check a different server for old results. A result is saved internally before the export to the chosen folder is attempted.

V0.3.0 adds `transcribe` with the same audio/header shape. It saves the received audio and runs inference synchronously, with no detached child and no polling. It returns the completed transcript or failed status. An existing model lock fails the quick request promptly; there is no hidden queue/local fallback. Duplicate completed requests return the saved result. Deferred recordings continue to use `submit` unchanged. Older workers reject the new operation and must be updated for quick dictation; the protocol schema remains 1 for existing operations.

V0.4.0 adds `prepare`, with `root` and validated `options` but no audio or job identifier. It exclusively acquires `engine.lock` without waiting, downloads/loads the selected model and exercises transcription on generated silence. If diarization is selected it loads that pipeline afterwards using the worker account's existing model access. It returns `state: ready`, `version`, `protocolVersion: 1`, `model` and resolved `device`, or a sanitized error. `probe` advertises `supportsModelPreparation: true`; probing itself still does not import the model runtime. The client allows up to thirty minutes and supports cancellation. Quick `transcribe` uses `local_files_only=True`; prepare it on the same worker account first. Deferred `submit` may still download its selected model on first use. No preparation process or model remains at idle.

New optional app metadata includes job kind, exported Markdown path, automatic-summary configuration captured for a recording, and summary state/paths. Missing fields preserve old history. Summary jobs interrupted by app shutdown/restart require manual retry. Dictation target handles are memory-only and are never recovered for delayed insertion.
