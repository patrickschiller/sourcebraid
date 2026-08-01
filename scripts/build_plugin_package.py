#!/usr/bin/env python3
"""Build the public skills-only SourceBraid plugin package."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath


PLUGIN_FILES = (
    "assets/chrome-capture.png",
    "assets/codex-search.png",
    "assets/private-markdown-archive.png",
    "assets/sourcebraid-icon.png",
    "scripts/sourcebraid.py",
    "skills/sourcebraid-delete/SKILL.md",
    "skills/sourcebraid-delete/agents/openai.yaml",
    "skills/sourcebraid-index/SKILL.md",
    "skills/sourcebraid-index/agents/openai.yaml",
    "skills/sourcebraid-search/SKILL.md",
    "skills/sourcebraid-search/agents/openai.yaml",
)

VERSION_PATTERN = re.compile(
    r"^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)


class PluginPackageError(RuntimeError):
    """Raised when the public plugin package cannot be built safely."""


def public_manifest(plugin_root: Path) -> dict[str, object]:
    manifest_path = plugin_root / ".codex-plugin" / "plugin.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PluginPackageError(f"could not read plugin manifest: {error}") from error
    if manifest.get("name") != "sourcebraid":
        raise PluginPackageError("plugin manifest name must be sourcebraid")
    version = manifest.get("version")
    if not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
        raise PluginPackageError("plugin manifest contains an invalid semantic version")
    if manifest.get("skills") != "./skills/":
        raise PluginPackageError("plugin manifest must point skills at ./skills/")

    # The first public release is deliberately skills-only. The local source
    # package keeps its bundled stdio MCP server for development and repo use.
    manifest.pop("mcpServers", None)
    manifest.pop("apps", None)
    return manifest


def validated_files(plugin_root: Path) -> list[tuple[Path, str]]:
    result: list[tuple[Path, str]] = []
    for archive_name in PLUGIN_FILES:
        relative = PurePosixPath(archive_name)
        source = plugin_root.joinpath(*relative.parts)
        if source.is_symlink():
            raise PluginPackageError(f"refusing to package symlink: {archive_name}")
        if not source.is_file():
            raise PluginPackageError(f"required plugin file is missing: {archive_name}")
        result.append((source, relative.as_posix()))
    return result


def build_package(plugin_root: Path, output_path: Path) -> tuple[str, str]:
    manifest = public_manifest(plugin_root)
    files = validated_files(plugin_root)
    manifest_bytes = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(
        output_path,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        entries = [(None, ".codex-plugin/plugin.json", manifest_bytes)] + [
            (source, archive_name, None) for source, archive_name in files
        ]
        for source, archive_name, generated in entries:
            info = zipfile.ZipInfo(archive_name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, generated if generated is not None else source.read_bytes())

    expected = tuple(sorted((".codex-plugin/plugin.json", *PLUGIN_FILES)))
    with zipfile.ZipFile(output_path) as archive:
        actual = tuple(sorted(archive.namelist()))
        packaged_manifest = json.loads(archive.read(".codex-plugin/plugin.json"))
    if actual != expected or "mcpServers" in packaged_manifest or "apps" in packaged_manifest:
        output_path.unlink(missing_ok=True)
        raise PluginPackageError("public plugin archive failed the skills-only allowlist check")

    digest = hashlib.sha256(output_path.read_bytes()).hexdigest()
    return str(manifest["version"]), digest


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Build the skills-only SourceBraid package for public plugin submission.",
    )
    result.add_argument(
        "--plugin-root",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "codex-plugin" / "sourcebraid",
    )
    result.add_argument("--output", type=Path)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    plugin_root = args.plugin_root.resolve()
    try:
        manifest = public_manifest(plugin_root)
        version = str(manifest["version"])
        safe_version = version.replace("+", "-")
        output = (
            args.output
            or plugin_root.parents[1] / "dist" / f"sourcebraid-plugin-skills-v{safe_version}.zip"
        ).resolve()
        version, digest = build_package(plugin_root, output)
    except PluginPackageError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"package: {output}")
    print(f"version: {version}")
    print("type: skills-only")
    print(f"sha256: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
