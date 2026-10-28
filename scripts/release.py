"""Check a release and prepare source-matched downloads; no network or publishing."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import subprocess
from urllib.parse import unquote, urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DOCS = (
    "SETUP.md", "USAGE.md", "DEVELOPMENT.md", "RELEASING.md", "MAC_TESTING.md",
    "PROTOCOL.md", "VALIDATION_V1.md", "VALIDATION_V2.md", "VALIDATION_V3.md", "VALIDATION_V4.md",
)
WORKER_FILES = (
    "VERSION", "LICENSE", "README.md", "CHANGELOG.md", "START_HERE.txt",
    "worker/murmure_worker.py", "worker/requirements.txt", "worker/requirements-diarization.txt",
    "scripts/setup-worker.ps1", "scripts/setup-worker.sh", "scripts/check-worker-runtime.py",
) + tuple(f"docs/{name}" for name in DOCS) + ("docs/assets/dictation-indicator.png",)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def changelog_entry(root, version):
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    match = re.search(rf"^## {re.escape(version)} — \d{{4}}-\d{{2}}-\d{{2}}\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    require(match and match[1].strip(), f"Missing dated changelog entry for {version}")
    return match[1].strip()


def check_links(root):
    for path in [root / "README.md", root / "CHANGELOG.md", root / "PROJECT_STATE.md", *sorted((root / "docs").glob("*.md"))]:
        if not path.exists():
            continue
        for link in re.findall(r"\]\(([^)\s]+)\)", path.read_text(encoding="utf-8")):
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            target = (path.parent / unquote(parsed.path)).resolve()
            require(target.is_relative_to(root.resolve()) and target.exists(), f"Broken local link in {path.name}: {link}")


def check_source(root=ROOT, tag=None):
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    require(re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version), "VERSION must be MAJOR.MINOR.PATCH")
    major, minor, patch = map(int, version.split("."))
    require(minor < 1000 and patch < 1000, "minor and patch must fit the numeric bundle build")
    require(tag is None or tag == f"v{version}", f"Tag {tag} does not match VERSION {version}")
    info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
    require(info["CFBundleShortVersionString"] == version, "Bundle version differs from VERSION")
    require(info["CFBundleVersion"] == str(major * 1000000 + minor * 1000 + patch), "Bundle build number differs from VERSION")
    module = ast.parse((root / "worker/murmure_worker.py").read_text(encoding="utf-8"))
    worker_version = next(ast.literal_eval(node.value) for node in module.body if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "VERSION" for t in node.targets))
    require(worker_version == version, "Worker version differs from VERSION")
    guide = (root / "START_HERE.txt").read_text(encoding="utf-8")
    require(guide.startswith(f"Murmure {version} —"), "Guide version differs from VERSION")
    names = re.findall(r"Murmure-(\d+\.\d+\.\d+)-(?:macOS|worker)\.zip", guide)
    require(len(names) >= 2 and set(names) == {version}, "Guide archive names differ from VERSION")
    require("MIT License" in (root / "LICENSE").read_text(encoding="utf-8"), "Missing MIT licence")
    changelog_entry(root, version)
    check_links(root)
    for name in WORKER_FILES:
        require((root / name).is_file(), f"Missing worker package source: {name}")
    return version


def package_worker(root, output):
    version = check_source(root)
    output.mkdir(parents=True, exist_ok=True)
    target = output / f"Murmure-{version}-worker.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in WORKER_FILES:
            entry = zipfile.ZipInfo(f"Murmure-worker/{name}")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | (0o755 if name.endswith(".sh") else 0o644)) << 16
            archive.writestr(entry, (root / name).read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
    return target


def archive_members(archive):
    members = [item for item in archive.infolist() if not item.is_dir()]
    names = [item.filename for item in members]
    require(len(set(names)) == len(names), "Duplicate archive entries")
    for item in members:
        require(not stat.S_ISLNK(item.external_attr >> 16), f"Unexpected symlink: {item.filename}")
    return set(names)


def check_archives(root, output, version):
    worker = output / f"Murmure-{version}-worker.zip"
    with zipfile.ZipFile(worker) as archive:
        expected = {f"Murmure-worker/{name}" for name in WORKER_FILES}
        require(archive_members(archive) == expected, "Worker ZIP contains missing or unexpected files")
        for name in WORKER_FILES:
            require(archive.read(f"Murmure-worker/{name}") == (root / name).read_bytes(), f"Packaged worker file differs from source: {name}")
        require(archive.getinfo("Murmure-worker/scripts/setup-worker.sh").external_attr >> 16 & 0o111, "Worker setup script is not executable")
    app = output / f"Murmure-{version}-macOS.zip"
    prefix = "Murmure.app/Contents/"
    with zipfile.ZipFile(app) as archive:
        expected = {prefix + name for name in ("Info.plist", "MacOS/Murmure", "Resources/murmure_worker.py", "Resources/START_HERE.txt", "Resources/LICENSE")}
        require(archive_members(archive) == expected, "App ZIP contains missing or unexpected files")
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        source_info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
        require(info == source_info, "Packaged bundle metadata differs from source")
        for source, name in (("worker/murmure_worker.py", "murmure_worker.py"), ("START_HERE.txt", "START_HERE.txt"), ("LICENSE", "LICENSE")):
            require(archive.read(prefix + "Resources/" + name) == (root / source).read_bytes(), f"Packaged app resource differs from source: {name}")
        executable = archive.read(prefix + "MacOS/Murmure")
        require(len(executable) >= 48 and executable[:4] == b"\xca\xfe\xba\xbe", "App is not a universal Mach-O binary")
        count = struct.unpack_from(">I", executable, 4)[0]
        require(count == 2, "Expected exactly two app architectures")
        architectures = {struct.unpack_from(">I", executable, 8 + 20 * index)[0] for index in range(count)}
        require(architectures == {0x01000007, 0x0100000C}, "App must include x86_64 and arm64")
        require(archive.getinfo(prefix + "MacOS/Murmure").external_attr >> 16 & 0o111, "App binary is not executable")
    guide = output / "START_HERE.txt"
    require(guide.read_bytes() == (root / "START_HERE.txt").read_bytes(), "Release guide differs from source")
    return (app, worker, guide)


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def prepare(root, output, tag, repository, run_url):
    version = check_source(root, tag)
    require(git(root, "status", "--porcelain", "--untracked-files=normal") == "", "Release checkout must be clean")
    commit = git(root, "rev-parse", "HEAD")
    require(git(root, "rev-list", "-n", "1", tag) == commit, "Checkout is not the tagged source")
    files = check_archives(root, output, version)
    records = {path.name: {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size} for path in files}
    sums = "".join(f"{record['sha256']}  {name}\n" for name, record in records.items())
    (output / "SHA256SUMS").write_text(sums, encoding="utf-8", newline="\n")
    metadata = {"version": version, "tag": tag, "source_commit": commit, "repository": repository,
                "build_run": run_url, "minimum_macos": "15.0", "architectures": ["arm64", "x86_64"],
                "developer_id_signed": False, "notarized": False, "experimental": True, "files": records}
    (output / "RELEASE.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8", newline="\n")
    notes = f"""Experimental macOS 15+ prerelease for Apple Silicon and Intel. Not Developer ID signed or notarized.

## Changes

{changelog_entry(root, version)}

## Download and install

Download both version-matched ZIPs, START_HERE.txt and SHA256SUMS below. Unzip the app into Applications and install the worker on your processing computer. Follow START_HERE.txt for SSH/model setup. Verify downloads on macOS with `shasum -a 256 -c SHA256SUMS`.

Quit the old app before upgrading; keep your recording/data folders and update the worker too. Back up Application Support before downgrading.

## Validation

[Build and test run]({run_url}) at source `{commit}`. Both CI platforms and archive/source checks must pass before this draft is created. RELEASE.json records source identity and download hashes.

Live Mac capture, permissions, shortcut/editor input, real SSH, GPU/diarization, CLI accounts and idle energy still need testing. Build/synthetic tests do not prove those paths. Use the [Mac checklist](https://github.com/{repository}/blob/{tag}/docs/MAC_TESTING.md) before relying on important recordings.
"""
    (output / "release-notes.md").write_text(notes, encoding="utf-8", newline="\n")
    print(f"Prepared {tag} from {commit}; archives match source. Nothing published.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "worker", "archives", "prepare"))
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--tag")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "CaillouMalade/Murmure"))
    parser.add_argument("--run-url", default="")
    args = parser.parse_args()
    if args.command == "check":
        print(f"Version, changelog and local links passed: {check_source(ROOT, args.tag)}")
    elif args.command == "worker":
        print(package_worker(ROOT, args.output))
    elif args.command == "archives":
        version = check_source(ROOT, args.tag)
        check_archives(ROOT, args.output, version)
        print(f"App, worker and guide match source: {version}")
    else:
        if not args.tag or not args.run_url:
            parser.error("prepare requires --tag and --run-url")
        prepare(ROOT, args.output, args.tag, args.repository, args.run_url)


if __name__ == "__main__":
    main()
