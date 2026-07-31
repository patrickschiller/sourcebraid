import json
import os
import tempfile
import unittest
from pathlib import Path

from scripts.convert_pdfs import (
    extract_frontmatter,
    extract_notes,
    frontmatter_value,
    rewrite_artifact_links,
    update_frontmatter,
    update_index,
)


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
