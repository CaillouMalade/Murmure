# Releasing Murmure

Use immutable `vMAJOR.MINOR.PATCH` tags. While the app is experimental, releases are marked **prerelease**. Never move an existing tag or replace published assets; fix mistakes in a new version. Earlier v0.1.0–v0.4.1 tags remain development milestones, not retroactively rebuilt releases.

## Prepare a version

1. Update `VERSION`, `worker/murmure_worker.py`'s `VERSION`, both bundle versions in `Resources/Info.plist`, and versioned names in `START_HERE.txt`. The numeric bundle build is `major * 1000000 + minor * 1000 + patch`; minor and patch must be below 1000.
2. Add the version's dated entry to `CHANGELOG.md`. Describe behavior, compatibility, testing limits and required worker updates. Update setup/usage docs when needed.
3. Run the development checks, review the diff and merge to main. `python scripts/release.py check` rejects version/changelog disagreements and validates local Markdown links. Keep the working tree clean before tagging.
4. Tag that exact commit and push it:

```bash
git tag -a v0.4.2 -m "Murmure 0.4.2"
git push origin v0.4.2
```

Use the new version in these commands on subsequent releases. The version checker requires an exact tag match; do not reuse a milestone tag.

## What the workflow does

`Prepare release` runs both Windows and macOS CI at the tag's commit, scans history for secrets and checks that the tag belongs to main. Only if all checks pass does it download the Mac build from that same workflow run, revalidate the archives against source, and create a **draft prerelease**. It never publishes automatically and refuses to replace an existing release, including on reruns.

Each draft contains:

- `Murmure-<version>-macOS.zip`, a universal macOS 15+ app with the MIT licence and first-run guide.
- `Murmure-<version>-worker.zip`, the matching worker, pinned requirement lists, setup scripts, licence and public documentation. No models, venvs, recordings or private development notes are packaged.
- `START_HERE.txt` and `SHA256SUMS`, covering both archives and the guide.
- `RELEASE.json`, recording the version, exact source commit, build run, sizes/hashes, minimum macOS and unsigned/non-notarized status.

Release notes come from the exact version's changelog entry and include installation, upgrade and remaining native-testing limits. The latest published experimental release may not appear under GitHub's `/releases/latest` route, so documentation links to the full Releases list.

If a draft already exists, inspect it instead of rerunning upload commands. For a failed first build, fix source and tag a new version. A transient failed run that created no draft can be rerun. Downloaded artifacts are temporary; published release assets are the download channel.

## Review and publish

Open the draft in [Releases](https://github.com/CaillouMalade/Murmure/releases), review its notes, download the app/worker pair and verify the checksums. Test on a real Mac using [MAC_TESTING.md](MAC_TESTING.md). Leave **prerelease** selected until the live checks support a stable release. Publishing the draft is an explicit maintainer action.

Repository visibility is also a separate maintainer action. The current source has public documentation and an MIT licence; earlier commits, milestone ZIPs and Actions logs may still contain historical development notes. Removing a current file does not erase its history. No history rewrite or old-release deletion is part of this process.
