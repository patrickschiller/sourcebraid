#!/usr/bin/env python3
"""Build the public, synthetic review archive without reading a user's clips."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path


FIXTURES = (
    ("durable-markdown-archives", "f4", "durable Markdown archives", ("review", "markdown", "ownership"),
     "This synthetic review source describes a portable weave of Markdown files."),
    ("retrieval-workflows", "4e", "retrieval workflows", ("review", "ai", "retrieval"),
     "This synthetic review source describes an incremental retrieval index."),
    ("deletion-safety", "20", "deletion safety", ("review", "safety", "deletion"),
     "This synthetic review source requires a fresh preview and explicit confirmation."),
)


def fixture_files() -> dict[str, bytes]:
    """Return only hard-coded, redistributable fixtures and their URL-hash shards."""
    files: dict[str, bytes] = {}
    for slug, shard, title_suffix, tags, body in FIXTURES:
        url = f"https://example.com/sourcebraid-review/{slug}"
        title = f"Synthetic review: {title_suffix}"
        path = f"web-clips/review/{slug}.md"
        metadata = {
            "url": url, "title": title, "path": path, "date": "2026-08-24",
            "source": "synthetic", "tags": list(tags), "assets": [],
        }
        markdown = (
            f"---\ntitle: {json.dumps(title)}\nurl: {json.dumps(url)}\n"
            f'date: "2026-08-24"\nsource: "synthetic"\ntags: {json.dumps(tags)}\n'
            f"---\n\n{body}\n"
        )
        files[path] = markdown.encode("utf-8")
        shard_path = f"web-clips/index/{shard}.jsonl"
        line = json.dumps(metadata, separators=(",", ":")) + "\n"
        files[shard_path] = files.get(shard_path, b"") + line.encode("utf-8")
    return files


def build_package(output_path: Path) -> str:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in sorted(fixture_files().items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    return hashlib.sha256(output_path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    digest = build_package(args.output)
    print(f"synthetic fixture: {args.output}\nsha256: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
