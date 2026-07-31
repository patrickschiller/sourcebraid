#!/usr/bin/env python3
# Managed by SourceBraid PDF support.
"""Convert queued web-clip PDFs with Docling and update their Markdown/index."""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ZERO_SHA = "0" * 40
NOTES_PATTERN = re.compile(
    r"<!-- clipper-notes-start -->.*?<!-- clipper-notes-end -->\s*",
    re.DOTALL,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", default="")
    parser.add_argument("--after", default="HEAD")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()

    sources = discover_sources(args.before, args.after, args.all)
    if not sources:
        print("No queued source.pdf files found.")
        return 0

    for source in sources:
        convert_source(source)
    return 0


def discover_sources(before: str, after: str, process_all: bool) -> list[Path]:
    if process_all or not before or before == ZERO_SHA:
        candidates = Path(".").glob("**/assets/*/source.pdf")
    else:
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=AM", before, after, "--", "**/assets/*/source.pdf"],
            check=True,
            capture_output=True,
            text=True,
        )
        candidates = (Path(line) for line in result.stdout.splitlines())

    return sorted(
        path for path in candidates
        if path.is_file() and path.name == "source.pdf" and path.parent.parent.name == "assets"
    )


def convert_source(source: Path) -> None:
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling_core.types.doc import ImageRefMode

    source = source.resolve()
    clip_slug = source.parent.name
    target = source.parent.parent.parent / f"{clip_slug}.md"
    pending = target.read_text(encoding="utf-8") if target.exists() else ""
    frontmatter = extract_frontmatter(pending)
    notes = extract_notes(pending)

    pipeline_options = PdfPipelineOptions()
    pipeline_options.images_scale = 1.5
    pipeline_options.generate_picture_images = True
    pipeline_options.do_ocr = True
    pipeline_options.do_table_structure = True
    converter = DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
        }
    )
    result = converter.convert(source)

    export_path = source.parent / "docling-output.md"
    artifact_path = source.parent / "docling-output_artifacts"
    if artifact_path.exists():
        shutil.rmtree(artifact_path)
    result.document.save_as_markdown(export_path, image_mode=ImageRefMode.REFERENCED)
    body = export_path.read_text(encoding="utf-8").strip()
    export_path.unlink(missing_ok=True)

    artifact_prefix = source.parent.relative_to(target.parent).as_posix()
    body = rewrite_artifact_links(body, artifact_prefix)

    converted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    pages = len(result.document.pages)
    version = importlib.metadata.version("docling")
    frontmatter = update_frontmatter(
        frontmatter,
        {
            "capture_method": json.dumps("pdf-docling"),
            "conversion_status": json.dumps("complete"),
            "converter": json.dumps("docling"),
            "converter_version": json.dumps(version),
            "pages": str(pages),
            "ocr_enabled": "true",
            "converted_at": json.dumps(converted_at),
        },
    )

    title = frontmatter_value(frontmatter, "title") or clip_slug
    if not re.match(r"^#\s+", body):
        body = f"# {title}\n\n{body}"
    sections = [frontmatter.strip(), notes.strip(), body]
    target.write_text("\n\n".join(section for section in sections if section).rstrip() + "\n", encoding="utf-8")

    images = sorted(
        path.relative_to(Path.cwd()).as_posix()
        for path in source.parent.glob("docling-output_artifacts/**/*")
        if path.is_file()
    )
    update_index(target, source, images, pages, version, converted_at)
    print(f"Converted {source.relative_to(Path.cwd())} -> {target.relative_to(Path.cwd())}")


def extract_frontmatter(markdown: str) -> str:
    match = re.match(r"\A---\s*\n.*?\n---\s*", markdown, re.DOTALL)
    return match.group(0).strip() if match else "---\n---"


def extract_notes(markdown: str) -> str:
    match = NOTES_PATTERN.search(markdown)
    return match.group(0).strip() if match else ""


def rewrite_artifact_links(markdown: str, artifact_prefix: str) -> str:
    """Make Docling image links relative, regardless of its exported path style."""
    replacement = f"{artifact_prefix.rstrip('/')}/docling-output_artifacts/"
    return re.sub(
        r"(?<=\]\()[^)\n]*docling-output_artifacts/",
        lambda _match: replacement,
        markdown,
    )


def update_frontmatter(frontmatter: str, updates: dict[str, str]) -> str:
    lines = frontmatter.splitlines()
    if not lines or lines[0].strip() != "---":
        lines = ["---", "---"]
    if lines[-1].strip() != "---":
        lines.append("---")

    seen: set[str] = set()
    output = [lines[0]]
    for line in lines[1:-1]:
        match = re.match(r"^([A-Za-z0-9_-]+):", line)
        key = match.group(1) if match else ""
        if key in updates:
            output.append(f"{key}: {updates[key]}")
            seen.add(key)
        else:
            output.append(line)
    for key, value in updates.items():
        if key not in seen:
            output.append(f"{key}: {value}")
    output.append("---")
    return "\n".join(output)


def frontmatter_value(frontmatter: str, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}:\s*(.+)$", frontmatter, re.MULTILINE)
    if not match:
        return ""
    value = match.group(1).strip()
    try:
        decoded = json.loads(value)
        return str(decoded)
    except json.JSONDecodeError:
        return value.strip('"\'')


def update_index(
    target: Path,
    source: Path,
    images: list[str],
    pages: int,
    version: str,
    converted_at: str,
) -> None:
    root = target.parents[2]
    index_paths = [root / "index.jsonl"]
    shard_root = root / "index"
    if shard_root.exists():
        index_paths.extend(sorted(shard_root.glob("*.jsonl")))

    repository_root = Path.cwd().resolve()
    target_repo_path = target.resolve().relative_to(repository_root).as_posix()
    source_repo_path = source.resolve().relative_to(repository_root).as_posix()
    for index_path in index_paths:
        if not index_path.exists():
            continue
        output: list[str] = []
        changed = False
        for line in index_path.read_text(encoding="utf-8").splitlines():
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                output.append(line)
                continue
            if entry.get("path") == target_repo_path or entry.get("pdf_path") == source_repo_path:
                entry.update(
                    {
                        "capture_method": "pdf-docling",
                        "conversion_status": "complete",
                        "converter": "docling",
                        "converter_version": version,
                        "pages": pages,
                        "ocr_enabled": True,
                        "converted_at": converted_at,
                        "images": [{"path": image} for image in images],
                    }
                )
                changed = True
            output.append(json.dumps(entry, ensure_ascii=False, separators=(",", ":")))

        if changed:
            index_path.write_text("\n".join(output).rstrip() + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
