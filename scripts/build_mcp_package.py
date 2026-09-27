#!/usr/bin/env python3
"""Build the allowlisted deployable source archive for the ChatGPT MCP service."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath


MCP_FILES = (
    ("chatgpt-mcp/package.json", "package.json"),
    ("chatgpt-mcp/package-lock.json", "package-lock.json"),
    ("chatgpt-mcp/wrangler.jsonc", "wrangler.jsonc"),
    ("chatgpt-mcp/src/archive.mjs", "src/archive.mjs"),
    ("chatgpt-mcp/src/auth.mjs", "src/auth.mjs"),
    ("chatgpt-mcp/src/protocol.mjs", "src/protocol.mjs"),
    ("chatgpt-mcp/src/worker.mjs", "src/worker.mjs"),
    ("chatgpt-mcp/tests/archive.test.mjs", "tests/archive.test.mjs"),
    ("chatgpt-mcp/tests/auth.test.mjs", "tests/auth.test.mjs"),
    ("chatgpt-mcp/tests/protocol.test.mjs", "tests/protocol.test.mjs"),
    ("chatgpt-mcp/tests/worker.test.mjs", "tests/worker.test.mjs"),
    ("LICENSE", "LICENSE"),
    ("NOTICE", "NOTICE"),
    ("docs/CHATGPT_MCP_DEPLOYMENT.md", "DEPLOYMENT.md"),
)
VERSION_PATTERN = re.compile(r"^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$")


class MCPPackageError(RuntimeError):
    """The deployable MCP source package could not be built safely."""


def package_source(root: Path, relative: PurePosixPath) -> Path:
    if relative.is_absolute() or ".." in relative.parts:
        raise MCPPackageError(f"unsafe MCP source path: {relative}")
    source = root
    for part in relative.parts:
        source /= part
        if source.is_symlink():
            raise MCPPackageError(f"refusing to package symlink: {relative}")
    if not source.is_file():
        raise MCPPackageError(f"required MCP source file is missing: {relative}")
    return source


def validated_version(root: Path) -> str:
    try:
        package = json.loads(package_source(root, PurePosixPath("chatgpt-mcp/package.json")).read_bytes())
        lock = json.loads(package_source(root, PurePosixPath("chatgpt-mcp/package-lock.json")).read_bytes())
        version = package.get("version")
        if package.get("name") != "sourcebraid-chatgpt-mcp" or not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
            raise MCPPackageError("MCP package must have the SourceBraid name and a valid release version")
        if lock.get("version") != version or lock.get("packages", {}).get("", {}).get("version") != version:
            raise MCPPackageError("MCP lockfile version must match package.json")
        return version
    except (OSError, ValueError, TypeError, AttributeError) as error:
        raise MCPPackageError(f"could not read MCP package metadata: {error}") from error


def build_package(repository_root: Path, output_path: Path) -> tuple[str, str]:
    version = validated_version(repository_root)
    entries = []
    for source_name, archive_name in MCP_FILES:
        source = package_source(repository_root, PurePosixPath(source_name))
        relative = PurePosixPath(archive_name)
        if relative.is_absolute() or ".." in relative.parts:
            raise MCPPackageError(f"unsafe MCP archive path: {archive_name}")
        content = source.read_bytes()
        if archive_name == "DEPLOYMENT.md":
            for relative in ("../PRIVACY.md", "../marketing/OPENAI_MCP_SUBMISSION.md"):
                public = f"https://github.com/patrickschiller/sourcebraid/blob/main/{relative[3:]}"
                content = content.replace(f"]({relative})".encode(), f"]({public})".encode())
        entries.append((archive_name, content))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    with zipfile.ZipFile(output_path) as archive:
        if sorted(archive.namelist()) != sorted(name for _, name in MCP_FILES):
            output_path.unlink(missing_ok=True)
            raise MCPPackageError("MCP source ZIP does not match the explicit allowlist")
    return version, hashlib.sha256(output_path.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    root = args.repository_root.resolve()
    try:
        version = validated_version(root)
        output = args.output or root / "dist" / f"sourcebraid-chatgpt-mcp-v{version}.zip"
        version, checksum = build_package(root, output)
    except (MCPPackageError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"package: {output}\nversion: {version}\nsha256: {checksum}\nfiles: {len(MCP_FILES)} (explicit allowlist)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
