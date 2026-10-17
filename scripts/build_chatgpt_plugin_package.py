#!/usr/bin/env python3
"""Build the remote-MCP plugin ZIP uploaded to the OpenAI submission portal."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

from build_mcp_package import MCPPackageError, package_source, validated_version


PLUGIN_FILES = (
    ("chatgpt-plugin/sourcebraid/plugin.json", "plugin.json"),
    ("chatgpt-plugin/sourcebraid/mcp.json", "mcp.json"),
    ("codex-plugin/sourcebraid/assets/sourcebraid-icon.png", "assets/sourcebraid-icon.png"),
)


class ChatGPTPluginPackageError(RuntimeError):
    """The hosted plugin package could not be prepared safely."""


def validate_metadata(manifest: dict, servers: dict, version: str) -> None:
    """Check SourceBraid's submission contract, not the entire external schema."""
    try:
        if manifest.get("name") != "sourcebraid" or manifest.get("version") != version:
            raise ChatGPTPluginPackageError("hosted plugin version must match the MCP service")
        if manifest.get("$schema") != "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json":
            raise ChatGPTPluginPackageError("hosted plugin must use the portable plugin schema")
        interface = manifest["extensions"]["com.openai"]["interface"]
        for key, limit in (("displayName", 30), ("shortDescription", 30), ("longDescription", 4000), ("developerName", 80)):
            value = interface[key]
            if not isinstance(value, str) or not value.strip() or len(value) > limit:
                raise ChatGPTPluginPackageError(f"invalid hosted plugin listing field: {key}")
        for key in ("websiteURL", "supportURL", "privacyPolicyURL", "termsOfServiceURL"):
            value = interface[key]
            url = urlsplit(value)
            if url.scheme != "https" or not url.hostname or url.username or url.password or len(value) > 1024:
                raise ChatGPTPluginPackageError(f"invalid hosted plugin URL: {key}")
        if interface["capabilities"] != ["Read"]:
            raise ChatGPTPluginPackageError("hosted plugin must advertise read-only access")
        for key in ("logo", "composerIcon"):
            if interface[key] != "./assets/sourcebraid-icon.png":
                raise ChatGPTPluginPackageError("hosted plugin icon must be included in the allowlist")
        expected_servers = {
            "$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
            "mcpServers": {
                "sourcebraid": {
                    "type": "streamable-http",
                    "url": "https://mcp.sourcebraid.com/mcp",
                    "extensions": {"com.openai": {"auth": {
                        "type": "oauth", "client": {"mode": "dcr"},
                        "baseScopes": ["archive:read"],
                    }}},
                },
            },
        }
        if servers != expected_servers:
            raise ChatGPTPluginPackageError("hosted MCP must use the production URL and credential-free read-only OAuth DCR")
    except (KeyError, TypeError, ValueError, AttributeError) as error:
        raise ChatGPTPluginPackageError("invalid hosted plugin metadata") from error


def build_package(root: Path, output: Path) -> tuple[str, str]:
    version = validated_version(root)
    entries = {
        name: package_source(root, PurePosixPath(source)).read_bytes()
        for source, name in PLUGIN_FILES
    }
    try:
        validate_metadata(json.loads(entries["plugin.json"]), json.loads(entries["mcp.json"]), version)
    except (ValueError, TypeError) as error:
        raise ChatGPTPluginPackageError("could not read hosted plugin metadata") from error
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    return version, hashlib.sha256(output.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    root = args.repository_root.resolve()
    try:
        version = validated_version(root)
        output = args.output or root / "dist" / f"sourcebraid-chatgpt-plugin-v{version}.zip"
        version, checksum = build_package(root, output)
    except (ChatGPTPluginPackageError, MCPPackageError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"package: {output}\nversion: {version}\nsha256: {checksum}\nfiles: {len(PLUGIN_FILES)} (explicit allowlist)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
