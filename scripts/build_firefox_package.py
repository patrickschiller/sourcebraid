#!/usr/bin/env python3
"""Build a Mozilla Add-ons ZIP and optional reviewer source ZIP from allowlists."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath

import build_chrome_package as shared


MANIFEST_OVERRIDES = "firefox-extension/manifest-overrides.json"
LICENSE_FILES = ("LICENSE", "NOTICE")
EXTENSION_FILES = {name: str(shared.EXTENSION_DIRECTORY / name) for name in shared.PACKAGE_FILES}
PACKAGE_FILES = (*EXTENSION_FILES, *LICENSE_FILES)
SOURCE_FILES = (
    *LICENSE_FILES,
    *shared.PDF_SUPPORT_FILES,
    *EXTENSION_FILES.values(),
    MANIFEST_OVERRIDES,
    "firefox-extension/BUILD.md",
    "scripts/build_chrome_package.py",
    "scripts/build_firefox_package.py",
)


def read_sources(root: Path) -> dict[str, bytes]:
    sources = {}
    for name in SOURCE_FILES:
        content = shared.package_source(root, PurePosixPath(name)).read_bytes()
        reason = shared.private_content_reason(content)
        if reason:
            raise shared.PackageError(f"potential {reason} in {name}")
        sources[name] = content
    for name in shared.PDF_SUPPORT_FILES:
        if sources[name] != sources[EXTENSION_FILES[name]]:
            raise shared.PackageError(f"bundled PDF support differs from the canonical source: {name}")
    return sources


def package_files(sources: dict[str, bytes]) -> tuple[str, dict[str, bytes]]:
    manifest = json.loads(sources[EXTENSION_FILES["manifest.json"]])
    overrides = json.loads(sources[MANIFEST_OVERRIDES])
    if not isinstance(manifest, dict) or not isinstance(overrides, dict):
        raise shared.PackageError("Firefox manifest inputs must be JSON objects")
    version = overrides.get("version")
    if not isinstance(version, str) or not shared.VERSION_PATTERN.fullmatch(version):
        raise shared.PackageError("Firefox manifest overrides must specify a valid extension version")
    manifest.update(overrides)
    if manifest.get("manifest_version") != 3 or manifest.get("name") != "SourceBraid":
        raise shared.PackageError("Firefox package must identify SourceBraid and use Manifest V3")
    files = {name: sources[path] for name, path in EXTENSION_FILES.items()}
    files["manifest.json"] = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    files.update({name: sources[name] for name in LICENSE_FILES})
    return version, files


def require_clean_inputs(root: Path) -> str:
    def git(*args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(root), *args], check=True, capture_output=True, text=True,
        ).stdout.strip()

    try:
        commit = git("rev-parse", "HEAD")
        changes = git("status", "--porcelain", "--untracked-files=all", "--", *SOURCE_FILES)
    except (OSError, subprocess.CalledProcessError) as error:
        raise shared.PackageError("could not verify Firefox release inputs against a Git commit") from error
    if changes:
        raise shared.PackageError("Firefox release inputs must be committed and clean before building")
    return commit


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, help="Defaults to dist/sourcebraid-firefox-vVERSION.zip.")
    parser.add_argument("--source-output", type=Path, help="Also write a source ZIP for Mozilla review.")
    parser.add_argument("--require-clean", action="store_true", help="Require committed, unchanged Firefox inputs.")
    args = parser.parse_args(argv)
    root = args.repository_root.resolve()
    try:
        commit = require_clean_inputs(root) if args.require_clean else None
        sources = read_sources(root)
        version, files = package_files(sources)
        output = (args.output or root / "dist" / f"sourcebraid-firefox-v{version}.zip").resolve()
        source_output = args.source_output.resolve() if args.source_output else None
        if source_output == output:
            raise shared.PackageError("choose different paths for the add-on ZIP and source ZIP")
        if commit and (require_clean_inputs(root) != commit or read_sources(root) != sources):
            raise shared.PackageError("Firefox release inputs changed during the build")
        digest = shared.write_package(output, files)
        print(f"package: {output}\nversion: {version}\nsha256: {digest}")
        if source_output:
            source_digest = shared.write_package(source_output, sources)
            print(f"source package: {source_output}\nsha256: {source_digest}")
        if commit:
            print(f"source commit: {commit}")
    except (shared.PackageError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
