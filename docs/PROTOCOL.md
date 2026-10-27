# Worker protocol, schema 1

The app launches either system SSH or a configured local Python executable. There is no listening HTTP service. The remote command is `<python> -u <worker.py> rpc`; the SSH alias and the two executable/script tokens are validated before any remote shell sees them. Remote paths containing whitespace or shell punctuation are deliberately unsupported in the first version.

Each invocation receives one UTF-8 JSON header terminated by a newline (at most 16 KiB). `submit` is followed by exactly `bytes` bytes of M4A audio, transferred in chunks. The response is one JSON object on stdout. Logs from inference go to the job folder, not the SSH response stream. This is an internal protocol, not an internet-facing service.

```json
{"op":"submit","root":"~/.murmure","id":"e6d87382-6176-43c0-a33a-c44b64a8be4d","bytes":12345,"options":{"model":"small","language":"","device":"auto","diarization":false,"timestamps":true}}
```

`probe` returns worker version and whether Faster Whisper is installed, without importing the model runtime. `status` takes `root` and `id` and returns `missing`, `receiving`, `queued`, `running`, `completed` or `failed`. Failed responses contain `error`; completed responses contain a `transcript` with `language` and `segments` (`start`, `end`, `text`, optional `speaker`). A protocol rejection returns `state: error`.

Submission uses UUID directories, an OS file lock, a partial audio file, atomic JSON replacement and a detached subprocess. Duplicate submission of a queued/running/completed job consumes the input without launching another model process. A failed submission can be retried with the same ID. A separate lock serializes inference across jobs. No model import happens in the submit/status processes.

The app retains the connection settings used by each job so changing Settings does not silently check a different server for old results. A result is saved internally before the export to the chosen folder is attempted.
