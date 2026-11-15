import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.convert_pdfs import (
    discover_sources,
    extract_frontmatter,
    extract_notes,
    frontmatter_value,
    rewrite_artifact_links,
    update_frontmatter,
    update_index,
)


class DiscoverPdfSourcesTest(unittest.TestCase):
    MISSING_BEFORE = "f" * 40
    MISSING_AFTER = "e" * 40

    def setUp(self):
        original_cwd = Path.cwd()
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        os.chdir(self.root)
        self.addCleanup(os.chdir, original_cwd)
        self.git("init", "--quiet")
        self.git("config", "user.name", "SourceBraid Test")
        self.git("config", "user.email", "fixtures@example.com")

    def git(self, *args):
        result = subprocess.run(
            ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", *args],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def write_source(self, slug, content=b"%PDF synthetic fixture"):
        path = Path("web-clips/2026/11/assets") / slug / "source.pdf"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "--quiet", "--allow-empty", "-m", "Synthetic fixture update")
        return self.git("rev-parse", "HEAD")

    def test_valid_range_discovers_only_added_and_modified_source_pdfs(self):
        self.write_source("unchanged")
        modified = self.write_source("modified")
        removed = self.write_source("removed")
        before = self.commit()

        modified.write_bytes(b"%PDF changed synthetic fixture")
        removed.unlink()
        added = self.write_source("added", b"%PDF newly added synthetic fixture")
        ignored = added.parent / "attachment.pdf"
        ignored.write_bytes(b"%PDF unrelated attachment")
        after = self.commit()
        self.write_source("untracked")

        self.assertEqual(
            discover_sources(before, after, False),
            sorted([added, modified]),
        )

    def test_missing_before_discovers_current_pdfs_including_unchanged_sources(self):
        unchanged = self.write_source("unchanged")
        removed = self.write_source("removed")
        self.commit()

        removed.unlink()
        added = self.write_source("added")
        after = self.commit()

        self.assertEqual(
            discover_sources(self.MISSING_BEFORE, after, False),
            sorted([added, unchanged]),
        )

    def test_missing_before_without_pdfs_succeeds_without_docling(self):
        after = self.commit()
        script = Path(__file__).resolve().parents[1] / "scripts" / "convert_pdfs.py"
        # Isolated Python without site packages verifies the no-work path needs no Docling.
        result = subprocess.run(
            [
                sys.executable, "-I", "-S", str(script),
                "--before", self.MISSING_BEFORE, "--after", after,
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("No queued source.pdf files found.", result.stdout)

    def test_missing_before_does_not_hide_invalid_after(self):
        self.write_source("current")
        self.commit()

        with self.assertRaises(subprocess.CalledProcessError):
            discover_sources(self.MISSING_BEFORE, self.MISSING_AFTER, False)


class ConvertPdfHelpersTest(unittest.TestCase):
    def test_rewrite_artifact_links_normalizes_absolute_and_relative_paths(self):
        markdown = (
            "![Absolute](/home/runner/work/repo/assets/example/docling-output_artifacts/a.png)\n"
            "![Relative](docling-output_artifacts/b.png)\n"
            "[Source](https://example.com/image.png)\n"
        )

        self.assertEqual(
            rewrite_artifact_links(markdown, "assets/example"),
            "![Absolute](assets/example/docling-output_artifacts/a.png)\n"
            "![Relative](assets/example/docling-output_artifacts/b.png)\n"
            "[Source](https://example.com/image.png)\n",
        )

    def test_frontmatter_and_notes_are_preserved_and_updated(self):
        pending = """---
title: "Example PDF"
capture_method: "pdf-docling-pending"
conversion_status: "pending"
---

<!-- clipper-notes-start -->
## Notes

Important context.

<!-- clipper-notes-end -->
"""
        frontmatter = update_frontmatter(
            extract_frontmatter(pending),
            {
                "capture_method": '"pdf-docling"',
                "conversion_status": '"complete"',
                "pages": "12",
            },
        )

        self.assertEqual(frontmatter_value(frontmatter, "title"), "Example PDF")
        self.assertIn('capture_method: "pdf-docling"', frontmatter)
        self.assertIn("pages: 12", frontmatter)
        self.assertIn("Important context.", extract_notes(pending))

    def test_index_entry_is_marked_complete(self):
        original_cwd = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                target = root / "web-clips/2026/07/example.md"
                source = root / "web-clips/2026/07/assets/example/source.pdf"
                target.parent.mkdir(parents=True)
                source.parent.mkdir(parents=True)
                target.write_text("pending", encoding="utf-8")
                source.write_bytes(b"%PDF")
                index = root / "web-clips/index.jsonl"
                index.write_text(
                    json.dumps(
                        {
                            "path": "web-clips/2026/07/example.md",
                            "pdf_path": "web-clips/2026/07/assets/example/source.pdf",
                            "conversion_status": "pending",
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )

                update_index(
                    target,
                    source,
                    ["web-clips/2026/07/assets/example/docling-output_artifacts/picture.png"],
                    3,
                    "2.99.0",
                    "2026-07-18T10:00:00Z",
                )
                entry = json.loads(index.read_text(encoding="utf-8"))
                self.assertEqual(entry["conversion_status"], "complete")
                self.assertEqual(entry["capture_method"], "pdf-docling")
                self.assertEqual(entry["pages"], 3)
            finally:
                os.chdir(original_cwd)

    def test_sharded_index_entry_is_marked_complete(self):
        original_cwd = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            os.chdir(root)
            try:
                target = root / "web-clips/2026/07/example.md"
                source = root / "web-clips/2026/07/assets/example/source.pdf"
                target.parent.mkdir(parents=True)
                source.parent.mkdir(parents=True)
                target.write_text("pending", encoding="utf-8")
                source.write_bytes(b"%PDF")
                index = root / "web-clips/index/ab.jsonl"
                index.parent.mkdir(parents=True)
                index.write_text(
                    json.dumps(
                        {
                            "path": "web-clips/2026/07/example.md",
                            "pdf_path": "web-clips/2026/07/assets/example/source.pdf",
                            "conversion_status": "pending",
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )

                update_index(target, source, [], 4, "2.99.0", "2026-07-18T10:00:00Z")
                entry = json.loads(index.read_text(encoding="utf-8"))
                self.assertEqual(entry["conversion_status"], "complete")
                self.assertEqual(entry["pages"], 4)
            finally:
                os.chdir(original_cwd)


if __name__ == "__main__":
    unittest.main()
