"""Child helper for the real Windows kill-on-close tests; never uses models."""
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import murmure_worker as worker

kernel = ctypes.WinDLL("kernel32", use_last_error=True)
kernel.OpenEventW.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.LPCWSTR]
kernel.OpenEventW.restype = wintypes.HANDLE
kernel.SetEvent.argtypes = [wintypes.HANDLE]
kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel.CloseHandle.argtypes = [wintypes.HANDLE]

if sys.argv[1] == "broker":
    # Parent assigns this process to a test job object before releasing stdin.
    sys.stdin.buffer.read(1)
    with open(os.devnull, "wb") as log:
        try:
            worker.spawn_detached([sys.executable, __file__, "child", *sys.argv[2:]], log)
            print(json.dumps({"launched": True}), flush=True)
        except worker.WorkerError as error:
            print(json.dumps({"error": str(error)}), flush=True)
            sys.exit(0)
    sys.stdin.buffer.read()  # Remain alive until the test's job object kills us.
else:
    ready, finish, done = [kernel.OpenEventW(0x100002, False, name) for name in sys.argv[2:5]]
    if not all((ready, finish, done)):
        sys.exit(2)
    try:
        kernel.SetEvent(ready)
        if kernel.WaitForSingleObject(finish, 10_000) == 0:
            Path(sys.argv[5]).write_text("survived", encoding="utf-8")
            kernel.SetEvent(done)
    finally:
        for handle in (ready, finish, done):
            kernel.CloseHandle(handle)
