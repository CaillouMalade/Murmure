"""Release guard regression tests using small, source-derived archive fixtures."""
import importlib.util
import hashlib
import json
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "release.py"
SPEC = importlib.util.spec_from_file_location("release", SCRIPT)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "source"
        self.output = Path(self.temporary.name) / "output"
        self.output.mkdir()
        for name in (*release.WORKER_FILES, "Resources/Info.plist", "PROJECT_STATE.md"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(release.ROOT / name, target)
        self.version = release.check_source(self.root)

    def archives(self):
        release.package_worker(self.root, self.output)
        shutil.copyfile(self.root / "START_HERE.txt", self.output / "START_HERE.txt")
        # Header fixture only: actual builds/lipo still run on macOS CI.
        binary = struct.pack(">II", 0xCAFEBABE, 2)
        binary += struct.pack(">IIIII", 0x01000007, 0, 48, 1, 0)
        binary += struct.pack(">IIIII", 0x0100000C, 0, 49, 1, 0) + b"\0\0"
        files = {
            "Info.plist": (self.root / "Resources/Info.plist").read_bytes(),
            "MacOS/Murmure": binary,
            "Resources/murmure_worker.py": (self.root / "worker/murmure_worker.py").read_bytes(),
            "Resources/START_HERE.txt": (self.root / "START_HERE.txt").read_bytes(),
            "Resources/LICENSE": (self.root / "LICENSE").read_bytes(),
        }
        path = self.output / f"Murmure-{self.version}-macOS.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in files.items():
                entry = zipfile.ZipInfo("Murmure.app/Contents/" + name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFREG | (0o755 if name == "MacOS/Murmure" else 0o644)) << 16
                archive.writestr(entry, data)
        return path

    def test_tag_and_worker_must_match_source_version(self):
        self.assertEqual(release.check_source(self.root, f"v{self.version}"), self.version)
        with self.assertRaisesRegex(ValueError, "Tag.*does not match"):
            release.check_source(self.root, "v99.0.0")
        path = self.root / "worker/murmure_worker.py"
        path.write_text(path.read_text(encoding="utf-8").replace(f'VERSION = "{self.version}"', 'VERSION = "99.0.0"'), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Worker version differs"):
            release.check_source(self.root)

    def test_broken_documentation_link_is_rejected(self):
        with (self.root / "README.md").open("a", encoding="utf-8") as handle:
            handle.write("\n[Missing](docs/not-shipped.md)\n")
        with self.assertRaisesRegex(ValueError, "Broken local link"):
            release.check_source(self.root)

    def test_matching_archives_pass_and_ignore_private_staging_files(self):
        (self.root / "private-recording.wav").write_bytes(b"not for shipping")
        self.archives()
        self.assertEqual(len(release.check_archives(self.root, self.output, self.version)), 3)

    def test_extra_worker_content_is_rejected(self):
        self.archives()
        path = self.output / f"Murmure-{self.version}-worker.zip"
        with zipfile.ZipFile(path, "a") as archive:
            archive.writestr("Murmure-worker/.env", "private material")
        with self.assertRaisesRegex(ValueError, "Worker ZIP contains"):
            release.check_archives(self.root, self.output, self.version)

    def test_stale_worker_or_guide_is_rejected(self):
        self.archives()
        with (self.root / "worker/murmure_worker.py").open("a", encoding="utf-8") as handle:
            handle.write("\n# Source changed after packaging\n")
        with self.assertRaisesRegex(ValueError, "Packaged worker file differs"):
            release.check_archives(self.root, self.output, self.version)

    def test_app_requires_both_architectures_and_executable_permission(self):
        path = self.archives()
        with zipfile.ZipFile(path) as archive:
            entries = [(item, archive.read(item)) for item in archive.infolist()]
        with zipfile.ZipFile(path, "w") as archive:
            for item, data in entries:
                if item.filename.endswith("MacOS/Murmure"):
                    item.external_attr = (stat.S_IFREG | 0o644) << 16
                archive.writestr(item, data)
        with self.assertRaisesRegex(ValueError, "not executable"):
            release.check_archives(self.root, self.output, self.version)
        with zipfile.ZipFile(path, "w") as archive:
            for item, data in entries:
                if item.filename.endswith("MacOS/Murmure"):
                    item.external_attr = (stat.S_IFREG | 0o755) << 16
                    data = b"thin or corrupt executable"
                archive.writestr(item, data)
        with self.assertRaisesRegex(ValueError, "not a universal"):
            release.check_archives(self.root, self.output, self.version)

    def test_prepare_records_provenance_and_refuses_dirty_source(self):
        self.archives()
        def git(*args):
            return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.DEVNULL, text=True).strip()
        git("init")
        git("add", ".")
        git("-c", "user.name=Release test", "-c", "user.email=release@example.invalid", "commit", "-m", "Fixture")
        tag = f"v{self.version}"
        git("tag", tag)
        release.prepare(self.root, self.output, tag, "example/Murmure", "https://example.invalid/build")
        metadata = json.loads((self.output / "RELEASE.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["source_commit"], git("rev-parse", "HEAD"))
        self.assertFalse(metadata["developer_id_signed"])
        for name, record in metadata["files"].items():
            self.assertEqual(hashlib.sha256((self.output / name).read_bytes()).hexdigest(), record["sha256"])
        with (self.root / "README.md").open("a", encoding="utf-8") as handle:
            handle.write("\nUncommitted change\n")
        with self.assertRaisesRegex(ValueError, "checkout must be clean"):
            release.prepare(self.root, self.output, tag, "example/Murmure", "https://example.invalid/build")


if __name__ == "__main__":
    unittest.main()
