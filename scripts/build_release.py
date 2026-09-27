#!/usr/bin/env python3
"""Build and verify the allowlisted Chrome/OpenAI/GitHub submission bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

import build_chrome_package as chrome
import build_mcp_package as mcp
import build_plugin_package as plugin
import build_review_fixture as review
import build_setup_package as setup


KIT_FILES = (
    "LICENSE", "NOTICE", "PRIVACY.md", "TERMS.md",
    "docs/CHATGPT_PLUGIN.md",
    "docs/CHATGPT_MCP_DEPLOYMENT.md",
    "marketing/OPENAI_PLUGIN_SUBMISSION.md",
    "marketing/OPENAI_MCP_SUBMISSION.md",
    "chrome-extension/STORE_LISTING.md",
    "chrome-extension/store-assets/README.md",
    "chrome-extension/store-assets/sourcebraid-chrome-capture-1280x800.png",
    "chrome-extension/store-assets/sourcebraid-private-archive-1280x800.png",
    "chrome-extension/store-assets/sourcebraid-promo-440x280.png",
    "codex-plugin/sourcebraid/assets/sourcebraid-icon.png",
    "codex-plugin/sourcebraid/assets/chrome-capture.png",
    "codex-plugin/sourcebraid/assets/private-markdown-archive.png",
    "codex-plugin/sourcebraid/assets/codex-search.png",
)
MANIFEST_NAME = "RELEASE_MANIFEST.json"
CHECKSUMS_NAME = "SHA256SUMS"
SECRET_PATTERNS = (
    ("GitHub credential", re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})")),
    ("private key", re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("personal absolute path", re.compile(rb"/(?:Users|home)/[A-Za-z0-9_.-]+/")),
)


class ReleaseError(RuntimeError):
    """A reproducible release could not be built or verified safely."""


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def safe_source(root: Path, relative: str) -> Path:
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts:
        raise ReleaseError(f"unsafe allowlist path: {relative}")
    current = root
    for part in path.parts:
        current /= part
        if current.is_symlink():
            raise ReleaseError(f"symlink in release source: {relative}")
    if not current.is_file():
        raise ReleaseError(f"missing release source: {relative}")
    return current


def scan_content(name: str, content: bytes) -> None:
    for label, pattern in SECRET_PATTERNS:
        if pattern.search(content):
            # Never include the matching secret itself in diagnostics.
            raise ReleaseError(f"potential {label} in {name}")


def artifact_names(version: str) -> dict[str, str]:
    return {
        "chrome": f"sourcebraid-chrome-v{version}.zip",
        "openai": f"sourcebraid-plugin-skills-v{version}.zip",
        "mcp": f"sourcebraid-chatgpt-mcp-v{version}.zip",
        "setup": f"sourcebraid-github-setup-v{version}.py",
        "fixture": f"sourcebraid-review-fixture-v{version}.zip",
    }


def source_inputs() -> tuple[str, ...]:
    return tuple(sorted(set((
        *KIT_FILES,
        *(f"chrome-extension/sourcebraid/{name}" for name in chrome.PACKAGE_FILES),
        "codex-plugin/sourcebraid/.codex-plugin/plugin.json",
        *(f"codex-plugin/sourcebraid/{name}" for name in plugin.PLUGIN_FILES),
        *(name for name, _ in mcp.MCP_FILES),
        str(setup.SETUP_SCRIPT), *setup.SUPPORT_FILES,
        "scripts/build_chrome_package.py", "scripts/build_plugin_package.py",
        "scripts/build_setup_package.py", "scripts/build_review_fixture.py",
        "scripts/build_release.py",
        "scripts/build_mcp_package.py",
    ))))


def provenance(root: Path, inputs: tuple[str, ...]) -> dict[str, object]:
    try:
        commit = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        status = subprocess.run(
            ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all", "--", *inputs],
            check=True, capture_output=True, text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return {"commit": None, "release_inputs_modified": None}
    return {"commit": commit, "release_inputs_modified": bool(status)}


def start_here(version: str) -> bytes:
    names = artifact_names(version)
    return f"""# SourceBraid {version} — release and submission bundle

Verify this directory before upload:

```bash
shasum -a 256 -c SHA256SUMS
```

From a SourceBraid checkout you can additionally inspect archive membership and
the safety checks with `python3 scripts/build_release.py --verify PATH_TO_THIS_DIRECTORY`.

- Chrome Web Store upload: `{names['chrome']}`. Listing and separate graphics:
  `chrome-extension/STORE_LISTING.md` and `chrome-extension/store-assets/`.
- ChatGPT connector source: `{names['mcp']}`. Deploy the service following
  `docs/CHATGPT_MCP_DEPLOYMENT.md`, then follow `marketing/OPENAI_MCP_SUBMISSION.md`
  to submit its HTTPS endpoint. This source ZIP is not the connector endpoint.
- Local/Codex skills package: `{names['openai']}`. Follow
  `marketing/OPENAI_PLUGIN_SUBMISSION.md`, including its runtime requirements.
  Separate listing graphics are in `codex-plugin/sourcebraid/assets/`.
- GitHub release download: `{names['setup']}` is the standalone setup script.
- Reviewer data: `{names['fixture']}` contains six generated synthetic Markdown
  and metadata files. Extract only into a dedicated, empty private review checkout.
  It is test data, not an end-user archive or a plugin upload.

Deutsch: Das Chrome-ZIP wird im Chrome Web Store eingereicht. Das MCP-ZIP enthält
den Server zum Bereitstellen; danach wird dessen HTTPS-Endpunkt bei OpenAI
eingereicht. Das GitHub-Setup-Skript ist eine Download-Datei für den GitHub Release.
Die Bau- und Prüfschritte veröffentlichen noch nichts.

`RELEASE_MANIFEST.json` records the source commit, whether allowlisted inputs
have uncommitted changes, and the SHA-256 of every source input and output.
A candidate built with modified inputs must be rebuilt from the reviewed clean
release commit before publication. No build step submits to a store or publishes
a GitHub release. Store account details, credentials, regional choices, and
approval/publication remain separate portal steps.

The bundle is constructed from explicit file allowlists. It excludes the
private website, user clips, local configuration, Git history, and caches.
The only `web-clips/` entries are the six hard-coded synthetic review fixtures.
High-confidence credential and personal-path scans are additional checks,
not a substitute for reviewing the final public diff and graphics.
""".encode("utf-8")


def verify_zip(path: Path, expected: tuple[str, ...], fixture: bool = False) -> None:
    with zipfile.ZipFile(path) as archive:
        if sorted(archive.namelist()) != sorted(expected):
            raise ReleaseError(f"archive does not match the explicit allowlist: {path.name}")
        for member in archive.infolist():
            if member.external_attr >> 16 & 0o170000 == 0o120000:
                raise ReleaseError(f"symlink in archive: {path.name}")
            content = archive.read(member)
            scan_content(f"{path.name}:{member.filename}", content)
            if fixture and content != review.fixture_files()[member.filename]:
                raise ReleaseError("synthetic review fixture differs from its generated source")


def verify_bundle(directory: Path) -> dict[str, object]:
    try:
        manifest_bytes = (directory / MANIFEST_NAME).read_bytes()
        scan_content(MANIFEST_NAME, manifest_bytes)
        manifest = json.loads(manifest_bytes)
        version = manifest["version"]
        if not isinstance(version, str) or not setup.VERSION_PATTERN.fullmatch(version):
            raise ReleaseError("invalid release manifest version")
        names = artifact_names(version)
        expected_payload = {*KIT_FILES, *names.values(), "START_HERE.md"}
        if manifest.get("format") != 1 or set(manifest["files"]) != expected_payload:
            raise ReleaseError("release manifest does not match the output allowlist")
        if set(manifest["source_files"]) != set(source_inputs()):
            raise ReleaseError("release manifest does not match the source allowlist")
        expected_files = {*expected_payload, MANIFEST_NAME, CHECKSUMS_NAME}
        found: set[str] = set()
        for path in directory.rglob("*"):
            if path.is_symlink():
                raise ReleaseError("symlink in release directory")
            if path.is_file():
                found.add(path.relative_to(directory).as_posix())
        if found != expected_files:
            raise ReleaseError("release directory contains missing or unexpected files")
        for name, record in manifest["files"].items():
            content = (directory / name).read_bytes()
            if digest(content) != record["sha256"] or len(content) != record["bytes"]:
                raise ReleaseError(f"release checksum mismatch: {name}")
            if not name.endswith(".zip"):
                scan_content(name, content)
        expected_checksums = "".join(
            f"{digest((directory / name).read_bytes())}  {name}\n"
            for name in sorted(expected_payload | {MANIFEST_NAME})
        )
        if (directory / CHECKSUMS_NAME).read_text(encoding="utf-8") != expected_checksums:
            raise ReleaseError("SHA256SUMS does not match the release contents")
        verify_zip(directory / names["chrome"], chrome.PACKAGE_FILES)
        verify_zip(directory / names["openai"], (".codex-plugin/plugin.json", *plugin.PLUGIN_FILES))
        verify_zip(directory / names["mcp"], tuple(name for _, name in mcp.MCP_FILES))
        verify_zip(directory / names["fixture"], tuple(review.fixture_files()), fixture=True)
        with zipfile.ZipFile(directory / names["openai"]) as archive:
            packaged_manifest = json.loads(archive.read(".codex-plugin/plugin.json"))
            if "mcpServers" in packaged_manifest or "apps" in packaged_manifest:
                raise ReleaseError("public OpenAI package is not skills-only")
            if packaged_manifest.get("version") != version:
                raise ReleaseError("OpenAI package version does not match the release")
        with zipfile.ZipFile(directory / names["chrome"]) as archive:
            if json.loads(archive.read("manifest.json")).get("version") != version:
                raise ReleaseError("Chrome package version does not match the release")
        with zipfile.ZipFile(directory / names["mcp"]) as archive:
            package = json.loads(archive.read("package.json"))
            lock = json.loads(archive.read("package-lock.json"))
            if package.get("version") != version or lock.get("version") != version or lock.get("packages", {}).get("", {}).get("version") != version:
                raise ReleaseError("ChatGPT MCP package version does not match the release")
        return manifest
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        raise ReleaseError(f"could not verify release bundle: {error}") from error


def assemble(root: Path, destination: Path) -> dict[str, object]:
    inputs = source_inputs()
    sources = {name: safe_source(root, name).read_bytes() for name in inputs}
    for name, content in sources.items():
        scan_content(name, content)
    for name in chrome.PDF_SUPPORT_FILES:
        if sources[name] != sources[f"chrome-extension/sourcebraid/{name}"]:
            raise ReleaseError(f"bundled PDF support differs from the canonical source: {name}")
    version = setup.release_version(root)
    if mcp.validated_version(root) != version:
        raise ReleaseError("ChatGPT MCP package version must match Chrome and Codex")
    names = artifact_names(version)
    chrome.build_package(root, destination / names["chrome"])
    plugin.build_package(root / "codex-plugin/sourcebraid", destination / names["openai"])
    setup.build_package(root, destination / names["setup"])
    review.build_package(destination / names["fixture"])
    mcp.build_package(root, destination / names["mcp"])
    for name in KIT_FILES:
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(sources[name])
    (destination / "START_HERE.md").write_bytes(start_here(version))
    if any(safe_source(root, name).read_bytes() != content for name, content in sources.items()):
        raise ReleaseError("release sources changed during the build; retry after editing is complete")
    files = {
        path.relative_to(destination).as_posix(): {"sha256": digest(path.read_bytes()), "bytes": path.stat().st_size}
        for path in sorted(destination.rglob("*")) if path.is_file()
    }
    manifest = {
        "format": 1, "product": "SourceBraid", "version": version,
        "source": provenance(root, inputs),
        "source_files": {name: digest(content) for name, content in sorted(sources.items())},
        "files": files,
    }
    (destination / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (destination / CHECKSUMS_NAME).write_text("".join(
        f"{digest((destination / name).read_bytes())}  {name}\n"
        for name in sorted({*files, MANIFEST_NAME})
    ), encoding="utf-8")
    return verify_bundle(destination)


def build_release(root: Path, output: Path, reproducible: bool = False) -> dict[str, object]:
    root = root.resolve()
    if output.is_symlink():
        raise ReleaseError("refusing a symlink as the output directory")
    # Canonicalize system aliases such as macOS /var and /tmp before checking scope.
    output = output.resolve()
    if output == root or any(output.is_relative_to(root / name) for name in ("website", "web-clips", ".git")):
        raise ReleaseError("release output must not be the repository root or private source directories")
    with tempfile.TemporaryDirectory(prefix="sourcebraid-release-") as temporary:
        staging = Path(temporary) / "first"
        manifest = assemble(root, staging)
        if reproducible:
            second = Path(temporary) / "second"
            assemble(root, second)
            if (staging / CHECKSUMS_NAME).read_bytes() != (second / CHECKSUMS_NAME).read_bytes():
                raise ReleaseError("repeated release builds produced different checksums")
        if output.exists() and any(output.iterdir()):
            # Only replace a fully verified prior build of this exact output layout.
            existing = verify_bundle(output)
            if set(existing["files"]) != set(manifest["files"]):
                raise ReleaseError("existing bundle has a different version or output layout; choose a new output directory")
        output.mkdir(parents=True, exist_ok=True)
        for source in sorted(staging.rglob("*")):
            if source.is_file():
                target = output / source.relative_to(staging)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read_bytes())
                if target.suffix == ".py":
                    target.chmod(0o755)
    return verify_bundle(output)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--verify", type=Path, help="Verify an existing bundle without building or writing anything.")
    parser.add_argument("--verify-reproducible", action="store_true", help="Build twice and compare all artifact checksums.")
    parser.add_argument("--expected-version", help="Fail when the release version differs from a tag or requested version.")
    parser.add_argument("--require-clean", action="store_true", help="Require a Git commit with unchanged release inputs before building.")
    args = parser.parse_args(argv)
    try:
        if args.verify:
            if args.output_dir or args.verify_reproducible:
                parser.error("--verify cannot be combined with build output options")
            output = args.verify.resolve()
            manifest = verify_bundle(output)
        else:
            root = args.repository_root.resolve()
            version = setup.release_version(root)
            if args.expected_version and version != args.expected_version:
                raise ReleaseError("release version does not match --expected-version")
            if args.require_clean and provenance(root, source_inputs())["release_inputs_modified"] is not False:
                raise ReleaseError("release inputs must be committed and clean before building")
            output = args.output_dir or root / "dist" / f"sourcebraid-release-v{version}"
            manifest = build_release(root, output, args.verify_reproducible)
        if args.expected_version and manifest["version"] != args.expected_version:
            raise ReleaseError("release version does not match --expected-version")
        if args.require_clean and manifest["source"]["release_inputs_modified"] is not False:
            raise ReleaseError("release inputs were not committed and clean")
    except (ReleaseError, chrome.PackageError, plugin.PluginPackageError, mcp.MCPPackageError, setup.SetupPackageError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"release: {output}\nversion: {manifest['version']}\nverified files: {len(manifest['files']) + 2}")
    print(f"source inputs modified: {manifest['source']['release_inputs_modified']}")
    print(f"checksums: {output / CHECKSUMS_NAME}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
