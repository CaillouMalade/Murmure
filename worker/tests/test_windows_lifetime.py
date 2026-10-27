"""Use an actual Windows job object: kill the broker and verify child survival."""
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid


class BasicLimit(ctypes.Structure):
    _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64), ("PerJobUserTimeLimit", ctypes.c_int64),
                ("LimitFlags", wintypes.DWORD), ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.c_size_t), ("PriorityClass", wintypes.DWORD), ("SchedulingClass", wintypes.DWORD)]


class IOCount(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in ("ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
                                                    "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]


class ExtendedLimit(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", BasicLimit), ("IoInfo", IOCount),
                ("ProcessMemoryLimit", ctypes.c_size_t), ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t), ("PeakJobMemoryUsed", ctypes.c_size_t)]


@unittest.skipUnless(sys.platform == "win32", "Windows job-object lifetime test")
class WindowsLifetimeTests(unittest.TestCase):
    def setUp(self):
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        for name, arguments, result in [
            ("CreateJobObjectW", [ctypes.c_void_p, wintypes.LPCWSTR], wintypes.HANDLE),
            ("SetInformationJobObject", [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD], wintypes.BOOL),
            ("AssignProcessToJobObject", [wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
            ("CreateEventW", [ctypes.c_void_p, wintypes.BOOL, wintypes.BOOL, wintypes.LPCWSTR], wintypes.HANDLE),
            ("SetEvent", [wintypes.HANDLE], wintypes.BOOL),
            ("WaitForSingleObject", [wintypes.HANDLE, wintypes.DWORD], wintypes.DWORD),
            ("CloseHandle", [wintypes.HANDLE], wintypes.BOOL),
        ]:
            function = getattr(self.kernel, name); function.argtypes = arguments; function.restype = result
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)

    def run_case(self, allow_breakaway):
        kernel = self.kernel
        job = kernel.CreateJobObjectW(None, None)
        self.assertTrue(job)
        limits = ExtendedLimit()
        limits.BasicLimitInformation.LimitFlags = 0x2000 | (0x800 if allow_breakaway else 0)  # KILL_ON_CLOSE / BREAKAWAY_OK
        self.assertTrue(kernel.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits)))
        token = uuid.uuid4().hex
        names = [f"Local\\MurmureTest-{token}-{kind}" for kind in ("ready", "finish", "done")]
        events = [kernel.CreateEventW(None, True, False, name) for name in names]
        output = Path(self.temporary.name) / "survival.txt"
        helper = Path(__file__).with_name("windows_lifetime_probe.py")
        broker = subprocess.Popen([sys.executable, str(helper), "broker", *names, str(output)],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertTrue(kernel.AssignProcessToJobObject(job, int(broker._handle)), ctypes.get_last_error())
            broker.stdin.write(b"x"); broker.stdin.flush()
            response = json.loads(broker.stdout.readline())
            if not allow_breakaway:
                self.assertIn("Windows refused", response["error"])
                self.assertFalse(output.exists())
                return
            if "error" in response:
                self.skipTest("The embedding host's outer job refuses breakaway; the refusal test covers that path.")
            self.assertTrue(response["launched"])
            self.assertEqual(kernel.WaitForSingleObject(events[0], 5_000), 0, "Detached child did not start")
            kernel.CloseHandle(job); job = None  # Kills the SSH-like broker, not the detached child.
            broker.wait(timeout=5)
            kernel.SetEvent(events[1])
            self.assertEqual(kernel.WaitForSingleObject(events[2], 5_000), 0, "Detached child died with the broker")
            self.assertEqual(output.read_text(encoding="utf-8"), "survived")
        finally:
            if job: kernel.CloseHandle(job)
            if broker.poll() is None: broker.kill()
            broker.wait(timeout=5)
            for handle in events: kernel.CloseHandle(handle)
            for stream in (broker.stdin, broker.stdout, broker.stderr): stream.close()

    def test_child_outlives_a_kill_on_close_session(self):
        self.run_case(allow_breakaway=True)

    def test_session_that_denies_breakaway_is_reported_without_bypass(self):
        self.run_case(allow_breakaway=False)


if __name__ == "__main__":
    unittest.main()
