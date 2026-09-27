#!/usr/bin/env python3
"""Build a standalone, allowlisted SourceBraid GitHub setup script."""

from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
import pprint
import re
import sys
from pathlib import Path, PurePosixPath


SETUP_SCRIPT = PurePosixPath("scripts/setup_github.py")
SUPPORT_FILES = (
    ".github/workflows/convert-pdfs.yml",
    "requirements-docling.txt",
    "scripts/convert_pdfs.py",
    "scripts/push_with_retry.py",
)
EMBEDDED_MARKER = "EMBEDDED_SUPPORT_FILES: dict[str, str] = {}"
VERSION_PATTERN = re.compile(r"^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$")


class SetupPackageError(RuntimeError):
    """Raised when the standalone setup artifact cannot be built safely."""


def package_source(root: Path, relative: PurePosixPath) -> Path:
    if relative.is_absolute() or ".." in relative.parts:
        raise SetupPackageError(f"unsafe setup path: {relative}")
    source = root
    for part in relative.parts:
        source /= part
        if source.is_symlink():
            raise SetupPackageError(f"refusing to package symlink: {relative}")
    if not source.is_file():
        raise SetupPackageError(f"required setup file is missing: {relative}")
    return source


def release_version(repository_root: Path) -> str:
    manifest_paths = (
        repository_root / "chrome-extension" / "sourcebraid" / "manifest.json",
        repository_root / "codex-plugin" / "sourcebraid" / ".codex-plugin" / "plugin.json",
    )
    versions: list[str] = []
    for manifest_path in manifest_paths:
        manifest_path = package_source(repository_root, PurePosixPath(manifest_path.relative_to(repository_root)))
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise SetupPackageError(f"could not read release manifest {manifest_path}: {error}") from error
        version = manifest.get("version")
        if not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
            raise SetupPackageError(f"invalid release version in {manifest_path}")
        versions.append(version)
    if len(set(versions)) != 1:
        raise SetupPackageError("Chrome and Codex plugin versions must match")
    return versions[0]


def embedded_support_files(repository_root: Path) -> dict[str, str]:
    embedded: dict[str, str] = {}
    for repo_path in SUPPORT_FILES:
        relative = PurePosixPath(repo_path)
        source = package_source(repository_root, relative)
        embedded[repo_path] = base64.b64encode(source.read_bytes()).decode("ascii")
    return embedded


def standalone_source(repository_root: Path) -> bytes:
    setup_path = package_source(repository_root, SETUP_SCRIPT)
    try:
        source = setup_path.read_text(encoding="utf-8")
    except OSError as error:
        raise SetupPackageError(f"could not read {SETUP_SCRIPT}: {error}") from error
    if source.count(EMBEDDED_MARKER) != 1:
        raise SetupPackageError("setup script does not contain the unique embedded-file marker")

    mapping = pprint.pformat(
        embedded_support_files(repository_root),
        sort_dicts=True,
        width=100,
    )
    generated = source.replace(EMBEDDED_MARKER, f"EMBEDDED_SUPPORT_FILES: dict[str, str] = {mapping}")
    try:
        ast.parse(generated, filename=str(SETUP_SCRIPT))
    except SyntaxError as error:
        raise SetupPackageError(f"generated setup script is invalid: {error}") from error
    return generated.encode("utf-8")


def build_package(repository_root: Path, output_path: Path) -> tuple[str, str]:
    version = release_version(repository_root)
    content = standalone_source(repository_root)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(content)
    output_path.chmod(0o755)
    return version, hashlib.sha256(content).hexdigest()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Build the standalone SourceBraid GitHub setup script from an explicit allowlist.",
    )
    result.add_argument(
        "--repository-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    result.add_argument("--output", type=Path)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    repository_root = args.repository_root.resolve()
    try:
        version = release_version(repository_root)
        output = (
            args.output
            or repository_root / "dist" / f"sourcebraid-github-setup-v{version}.py"
        ).resolve()
        version, digest = build_package(repository_root, output)
    except SetupPackageError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"package: {output}")
    print(f"version: {version}")
    print(f"sha256: {digest}")
    print(f"embedded files: {len(SUPPORT_FILES)} (explicit allowlist)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
