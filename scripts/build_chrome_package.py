#!/usr/bin/env python3
"""Build a privacy-safe Chrome Web Store ZIP from an explicit allowlist."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath


PACKAGE_FILES = (
    ".github/workflows/convert-pdfs.yml",
    "background.js",
    "capture-utils.js",
    "content.js",
    "icons/icon-16.png",
    "icons/icon-32.png",
    "icons/icon-48.png",
    "icons/icon-128.png",
    "manifest.json",
    "popup.css",
    "popup.html",
    "popup.js",
    "requirements-docling.txt",
    "scripts/convert_pdfs.py",
    "scripts/push_with_retry.py",
)

VERSION_PATTERN = re.compile(r"^(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){0,3}$")


class PackageError(RuntimeError):
    """Raised when a safe release archive cannot be created."""


def validated_manifest(repository_root: Path) -> dict[str, object]:
    manifest_path = repository_root / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PackageError(f"could not read manifest.json: {error}") from error

    if manifest.get("manifest_version") != 3:
        raise PackageError("manifest.json must use Manifest V3")
    if manifest.get("name") != "SourceBraid":
        raise PackageError("manifest.json must identify the extension as SourceBraid")

    version = manifest.get("version")
    if not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
        raise PackageError("manifest.json contains an invalid Chrome extension version")
    return manifest


def validated_package_files(repository_root: Path) -> list[tuple[Path, str]]:
    files: list[tuple[Path, str]] = []
    for archive_name in PACKAGE_FILES:
        relative = PurePosixPath(archive_name)
        if relative.is_absolute() or ".." in relative.parts:
            raise PackageError(f"unsafe package path: {archive_name}")
        source = repository_root.joinpath(*relative.parts)
        if source.is_symlink():
            raise PackageError(f"refusing to package symlink: {archive_name}")
        if not source.is_file():
            raise PackageError(f"required extension file is missing: {archive_name}")
        files.append((source, relative.as_posix()))
    return files


def build_package(repository_root: Path, output_path: Path) -> tuple[str, str]:
    manifest = validated_manifest(repository_root)
    files = validated_package_files(repository_root)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(
        output_path,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for source, archive_name in files:
            info = zipfile.ZipInfo(archive_name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes())

    with zipfile.ZipFile(output_path) as archive:
        packaged_names = tuple(sorted(archive.namelist()))
    expected_names = tuple(sorted(PACKAGE_FILES))
    if packaged_names != expected_names:
        output_path.unlink(missing_ok=True)
        raise PackageError("release archive does not match the explicit allowlist")

    digest = hashlib.sha256(output_path.read_bytes()).hexdigest()
    return str(manifest["version"]), digest


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Build the SourceBraid Chrome Web Store ZIP from an explicit allowlist.",
    )
    result.add_argument(
        "--repository-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="SourceBraid repository root (defaults to the parent of scripts/).",
    )
    result.add_argument(
        "--output",
        type=Path,
        help="Output ZIP path (defaults to dist/sourcebraid-chrome-vVERSION.zip).",
    )
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    repository_root = args.repository_root.resolve()
    try:
        manifest = validated_manifest(repository_root)
        version = str(manifest["version"])
        output = (args.output or repository_root / "dist" / f"sourcebraid-chrome-v{version}.zip").resolve()
        version, digest = build_package(repository_root, output)
    except PackageError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"package: {output}")
    print(f"version: {version}")
    print(f"sha256: {digest}")
    print(f"files: {len(PACKAGE_FILES)} (explicit allowlist)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
