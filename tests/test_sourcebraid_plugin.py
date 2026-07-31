import base64
import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).parents[1] / "codex-plugin" / "sourcebraid" / "scripts" / "sourcebraid.py"
SPEC = importlib.util.spec_from_file_location("sourcebraid_plugin_under_test", SCRIPT_PATH)
assert SPEC and SPEC.loader
sourcebraid = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = sourcebraid
SPEC.loader.exec_module(sourcebraid)


def encoded_content(text):
    return {"content": base64.b64encode(text.encode("utf-8")).decode("ascii")}


class SourceBraidPluginTests(unittest.TestCase):
    def setUp(self):
        self.config = sourcebraid.Config(
            owner="owner",
            repo="archive",
            branch="main",
            root_folder="web-clips",
            token="token",
        )

    def test_validate_clip_path_rejects_unsafe_or_non_markdown_paths(self):
        self.assertEqual(
            sourcebraid.validate_clip_path(self.config, "web-clips/2026/07/example.md"),
            "web-clips/2026/07/example.md",
        )
        for path in (
            "../example.md",
            "/web-clips/example.md",
            "web-clips/../example.md",
            "web-clips//example.md",
            "web-clips/index.jsonl",
            "web-clips/example.pdf",
        ):
            with self.subTest(path=path), self.assertRaises(sourcebraid.KnowledgeError):
                sourcebraid.validate_clip_path(self.config, path)

    def test_url_hash_matches_browser_implementation(self):
        self.assertEqual(sourcebraid.url_hash("https://www.example.com/posts/hello"), "477df9")
        self.assertEqual(
            sourcebraid.metadata_shard_path(self.config, "https://www.example.com/posts/hello"),
            "web-clips/index/47.jsonl",
        )

    def test_remove_index_entry_preserves_unrelated_and_malformed_lines(self):
        index_text = (
            '{"path":"web-clips/keep.md","title":"Keep"}\n'
            "historical malformed line\n"
            '{"path":"web-clips/delete.md","title":"Delete"}\n'
        )
        next_text, matches = sourcebraid.remove_index_entry(index_text, "web-clips/delete.md")

        self.assertEqual(len(matches), 1)
        self.assertIn("web-clips/keep.md", next_text)
        self.assertIn("historical malformed line", next_text)
        self.assertNotIn("web-clips/delete.md", next_text)

    def test_list_records_includes_indexed_and_orphaned_markdown(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            with mock.patch.object(sourcebraid, "CACHE_ROOT", Path(temporary_directory)):
                root = self.config.cache_dir / "web-clips" / "2026" / "07"
                root.mkdir(parents=True)
                (root / "indexed.md").write_text("---\ntitle: Indexed\n---\n", encoding="utf-8")
                (root / "orphan.md").write_text(
                    '---\ntitle: Orphan\nurl: "https://example.com/orphan"\nsite: example.com\n---\n',
                    encoding="utf-8",
                )
                index = self.config.cache_dir / "web-clips" / "index.jsonl"
                index.write_text(
                    json.dumps(
                        {
                            "path": "web-clips/2026/07/indexed.md",
                            "title": "Indexed",
                            "url": "https://example.com/indexed",
                            "date": "2026-07-18",
                            "source": "Example",
                            "tags": ["AI"],
                            "images": [{"path": "web-clips/2026/07/assets/indexed/image.webp"}],
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )

                records = sourcebraid.list_clip_records(self.config)
                filtered = sourcebraid.list_clip_records(self.config, query="indexed", tags=["ai"], source="exam")

        self.assertEqual({record["status"] for record in records}, {"indexed", "orphaned"})
        self.assertEqual(len(filtered), 1)
        self.assertEqual(filtered[0]["path"], "web-clips/2026/07/indexed.md")
        self.assertEqual(filtered[0]["asset_count"], 1)

    def test_sync_can_suppress_status_for_json_callers(self):
        tree = {
            "tree": [
                {"path": "web-clips/example.md", "type": "blob"},
                {"path": "web-clips/index.jsonl", "type": "blob"},
            ]
        }

        def fake_github_json(_config, path):
            if "/git/trees/" in path:
                return tree
            if "/contents/web-clips/example.md" in path:
                return encoded_content("---\ntitle: Example\n---\n")
            if "/contents/web-clips/index.jsonl" in path:
                return encoded_content('{"path":"web-clips/example.md"}\n')
            raise AssertionError(path)

        with tempfile.TemporaryDirectory() as temporary_directory:
            with mock.patch.object(sourcebraid, "CACHE_ROOT", Path(temporary_directory)):
                with mock.patch.object(sourcebraid, "github_json", side_effect=fake_github_json):
                    output = io.StringIO()
                    with contextlib.redirect_stdout(output):
                        sourcebraid.sync(self.config, quiet=True)

        self.assertEqual(output.getvalue(), "")

    def test_build_search_index_and_query_without_scanning_files(self):
        clip_path = "web-clips/2026/07/example.md"
        url = "https://example.com/article"
        shard_path = sourcebraid.metadata_shard_path(self.config, url)
        markdown = (
            '---\ntitle: "Fallback title"\nurl: "https://example.com/article"\n---\n'
            "Dynamic agents coordinate specialized workflows.\n"
        )
        metadata = json.dumps(
            {
                "path": clip_path,
                "title": "Indexed title",
                "url": url,
                "date": "2026-07-20",
                "source": "Example",
                "tags": ["AI", "agents"],
            }
        ) + "\n"
        tree = {
            "truncated": False,
            "tree": [
                {"path": clip_path, "type": "blob", "sha": "clip-sha"},
                {"path": shard_path, "type": "blob", "sha": "index-sha"},
            ],
        }

        with tempfile.TemporaryDirectory() as temporary_directory:
            with mock.patch.object(sourcebraid, "CACHE_ROOT", Path(temporary_directory)):
                with mock.patch.object(sourcebraid, "repository_snapshot", return_value=("head", "tree", tree)):
                    with mock.patch.object(
                        sourcebraid,
                        "download_repository_texts",
                        return_value={clip_path: markdown, shard_path: metadata},
                    ):
                        result = sourcebraid.build_search_index(self.config)
                with mock.patch.object(sourcebraid, "run_rg") as run_rg:
                    matches = sourcebraid.search_index_records(
                        self.config,
                        "dynamic agents",
                        tags=["ai"],
                        source="exam",
                    )

        self.assertEqual(result["documents"], 1)
        self.assertEqual(matches[0]["title"], "Indexed title")
        self.assertIn("[Dynamic] [agents]", matches[0]["excerpt"])
        run_rg.assert_not_called()

    def test_incremental_update_downloads_only_changed_text_files(self):
        clip_path = "web-clips/2026/07/example.md"
        old_tree = {
            "truncated": False,
            "tree": [{"path": clip_path, "type": "blob", "sha": "old-blob"}],
        }
        new_tree = {
            "truncated": False,
            "tree": [{"path": clip_path, "type": "blob", "sha": "new-blob"}],
        }
        old_markdown = "---\ntitle: Old\n---\nOld searchable phrase.\n"
        new_markdown = "---\ntitle: New\n---\nFresh searchable phrase.\n"

        with tempfile.TemporaryDirectory() as temporary_directory:
            with mock.patch.object(sourcebraid, "CACHE_ROOT", Path(temporary_directory)):
                with mock.patch.object(sourcebraid, "repository_snapshot", return_value=("old-head", "tree", old_tree)):
                    with mock.patch.object(
                        sourcebraid,
                        "download_repository_texts",
                        return_value={clip_path: old_markdown},
                    ):
                        sourcebraid.build_search_index(self.config)
                with mock.patch.object(sourcebraid, "repository_snapshot", return_value=("new-head", "tree", new_tree)):
                    with mock.patch.object(sourcebraid, "repository_text", return_value=new_markdown) as read_text:
                        result = sourcebraid.update_search_index(self.config)
                fresh = sourcebraid.search_index_records(self.config, "fresh searchable")
                old = sourcebraid.search_index_records(self.config, "old searchable")

        self.assertEqual(result["downloaded"], 1)
        read_text.assert_called_once_with(self.config, clip_path, "new-head")
        self.assertEqual(fresh[0]["title"], "New")
        self.assertEqual(old, [])

    def test_ten_thousand_document_fts_index_remains_fast(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            with mock.patch.object(sourcebraid, "CACHE_ROOT", Path(temporary_directory)):
                connection = sourcebraid.connect_search_index(self.config, create=True)
                started = time.monotonic()
                with connection:
                    for number in range(10_000):
                        path = f"web-clips/2026/07/document-{number:05d}.md"
                        body = f"Common archive text. Unique marker{number:05d}."
                        sourcebraid.upsert_document(
                            connection,
                            path,
                            f"sha-{number}",
                            body,
                            {
                                "title": f"Document {number}",
                                "url": f"https://example.com/{number}",
                                "date": "2026-07-20",
                                "source": "Example",
                                "tags": ["benchmark"],
                            },
                        )
                build_seconds = time.monotonic() - started
                connection.close()

                query_started = time.monotonic()
                matches = sourcebraid.search_index_records(self.config, "marker09999", tags=["benchmark"])
                query_seconds = time.monotonic() - query_started

        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0]["path"], "web-clips/2026/07/document-09999.md")
        self.assertLess(build_seconds, 20.0)
        self.assertLess(query_seconds, 2.0)

    def test_shard_migration_plan_partitions_legacy_metadata(self):
        legacy_path = "web-clips/index.jsonl"
        entries = [
            {"path": "web-clips/a.md", "url": "https://example.com/a", "title": "A"},
            {"path": "web-clips/b.md", "url": "https://example.org/b", "title": "B"},
        ]
        legacy_text = "\n".join(json.dumps(entry) for entry in entries) + "\nmalformed legacy line\n"
        tree = {"truncated": False, "tree": [{"path": legacy_path, "type": "blob"}]}

        with mock.patch.object(sourcebraid, "repository_snapshot", return_value=("head", "tree", tree)):
            with mock.patch.object(sourcebraid, "repository_text", return_value=legacy_text):
                plan = sourcebraid.build_shard_migration_plan(self.config)

        self.assertEqual(plan.entry_count, 2)
        self.assertEqual(sum(text.count("\n") for text in plan.shard_texts.values()), 2)
        self.assertEqual(plan.residual_legacy_text, "malformed legacy line\n")
        self.assertEqual(len(plan.warnings), 1)

    def test_shard_migration_requires_matching_confirmation_before_planning(self):
        with mock.patch.object(sourcebraid, "build_shard_migration_plan") as build_plan:
            with self.assertRaisesRegex(sourcebraid.KnowledgeError, "exactly match"):
                sourcebraid.apply_shard_migration(self.config, "head-a", "head-b")
        build_plan.assert_not_called()

    def test_shard_migration_creates_one_non_forced_atomic_commit(self):
        plan = sourcebraid.ShardMigrationPlan(
            repo=self.config.repo_slug,
            branch=self.config.branch,
            head_sha="head-sha",
            base_tree_sha="base-tree",
            legacy_path="web-clips/index.jsonl",
            entry_count=1,
            shard_texts={"web-clips/index/ab.jsonl": '{"path":"web-clips/a.md"}\n'},
            residual_legacy_text="",
            warnings=[],
        )
        calls = []

        def fake_request(_config, path, method="GET", payload=None):
            calls.append((method, path, payload))
            if method == "POST" and path.endswith("/git/blobs"):
                return {"sha": "shard-blob"}
            if method == "POST" and path.endswith("/git/trees"):
                return {"sha": "new-tree"}
            if method == "POST" and path.endswith("/git/commits"):
                return {"sha": "new-commit"}
            if method == "PATCH" and "/git/refs/heads/" in path:
                return {"object": {"sha": "new-commit"}}
            raise AssertionError((method, path, payload))

        with mock.patch.object(sourcebraid, "build_shard_migration_plan", return_value=plan):
            with mock.patch.object(sourcebraid, "current_branch_head", return_value=plan.head_sha):
                with mock.patch.object(sourcebraid, "github_json_request", side_effect=fake_request):
                    result = sourcebraid.apply_shard_migration(self.config, plan.head_sha, plan.head_sha)

        tree_payload = next(payload for method, path, payload in calls if path.endswith("/git/trees"))
        self.assertTrue(result["ok"])
        self.assertEqual(tree_payload["base_tree"], "base-tree")
        self.assertIn(
            {"path": "web-clips/index.jsonl", "mode": "100644", "type": "blob", "sha": None},
            tree_payload["tree"],
        )
        patch_payload = next(payload for method, _path, payload in calls if method == "PATCH")
        self.assertEqual(patch_payload, {"sha": "new-commit", "force": False})

    def test_build_delete_plan_lists_exact_safe_targets(self):
        clip_path = "web-clips/2026/07/example.md"
        image_path = "web-clips/2026/07/assets/example/image.webp"
        pdf_path = "web-clips/2026/07/assets/example/source.pdf"
        outside_path = "web-clips/shared/image.webp"
        index_text = json.dumps(
            {
                "path": clip_path,
                "title": "Example clip",
                "url": "https://example.com/article",
                "pdf_path": pdf_path,
                "images": [{"path": image_path}, {"path": outside_path}],
            }
        ) + "\n"
        tree = {
            "truncated": False,
            "tree": [
                {"path": clip_path, "type": "blob"},
                {"path": "web-clips/index.jsonl", "type": "blob"},
                {"path": image_path, "type": "blob"},
                {"path": pdf_path, "type": "blob"},
                {"path": outside_path, "type": "blob"},
            ],
        }

        def fake_github_json(_config, path):
            if "/git/ref/heads/" in path:
                return {"object": {"sha": "head-sha"}}
            if "/git/commits/" in path:
                return {"tree": {"sha": "tree-sha"}}
            if "/git/trees/" in path:
                return tree
            if "/contents/web-clips/index.jsonl" in path:
                return encoded_content(index_text)
            if "/contents/web-clips/2026/07/example.md" in path:
                return encoded_content('---\ntitle: "Example clip"\n---\nBody\n')
            raise AssertionError(path)

        with mock.patch.object(sourcebraid, "github_json", side_effect=fake_github_json):
            plan = sourcebraid.build_delete_plan(self.config, clip_path)

        self.assertEqual(plan.head_sha, "head-sha")
        self.assertEqual(plan.targets, [clip_path, image_path, pdf_path])
        self.assertTrue(plan.indexed)
        self.assertNotIn(clip_path, plan.next_index_text)
        self.assertEqual(len(plan.warnings), 1)
        self.assertIn("will be kept", plan.warnings[0])

    def test_build_delete_plan_rejects_duplicate_index_entries(self):
        clip_path = "web-clips/example.md"
        index_text = "\n".join([json.dumps({"path": clip_path}), json.dumps({"path": clip_path})]) + "\n"
        tree = {
            "truncated": False,
            "tree": [
                {"path": clip_path, "type": "blob"},
                {"path": "web-clips/index.jsonl", "type": "blob"},
            ],
        }

        def fake_github_json(_config, path):
            if "/git/ref/heads/" in path:
                return {"object": {"sha": "head"}}
            if "/git/commits/" in path:
                return {"tree": {"sha": "tree"}}
            if "/git/trees/" in path:
                return tree
            if "/contents/web-clips/index.jsonl" in path:
                return encoded_content(index_text)
            raise AssertionError(path)

        with mock.patch.object(sourcebraid, "github_json", side_effect=fake_github_json):
            with self.assertRaisesRegex(sourcebraid.KnowledgeError, "contains 2 entries"):
                sourcebraid.build_delete_plan(self.config, clip_path)

    def test_delete_requires_exact_confirmation_before_planning(self):
        with mock.patch.object(sourcebraid, "build_delete_plan") as build_plan:
            with self.assertRaisesRegex(sourcebraid.KnowledgeError, "exactly match"):
                sourcebraid.delete_clip(
                    self.config,
                    repo_path="web-clips/example.md",
                    expected_head="head",
                    confirm_path="web-clips/other.md",
                )
        build_plan.assert_not_called()

    def test_delete_rejects_changed_head_before_writes(self):
        plan = self.make_plan(head_sha="new-head")
        with mock.patch.object(sourcebraid, "build_delete_plan", return_value=plan):
            with mock.patch.object(sourcebraid, "github_json_request") as request:
                with self.assertRaisesRegex(sourcebraid.KnowledgeError, "branch head changed"):
                    sourcebraid.delete_clip(
                        self.config,
                        repo_path=plan.path,
                        expected_head="old-head",
                        confirm_path=plan.path,
                    )
        request.assert_not_called()

    def test_delete_creates_one_non_forced_atomic_commit(self):
        plan = self.make_plan()
        calls = []

        def fake_request(_config, path, method="GET", payload=None):
            calls.append((method, path, payload))
            if method == "POST" and path.endswith("/git/blobs"):
                return {"sha": "index-blob"}
            if method == "POST" and path.endswith("/git/trees"):
                return {"sha": "new-tree"}
            if method == "POST" and path.endswith("/git/commits"):
                return {"sha": "new-commit"}
            if method == "GET" and "/git/ref/heads/" in path:
                return {"object": {"sha": plan.head_sha}}
            if method == "PATCH" and "/git/refs/heads/" in path:
                return {"object": {"sha": "new-commit"}}
            raise AssertionError((method, path, payload))

        with mock.patch.object(sourcebraid, "build_delete_plan", return_value=plan):
            with mock.patch.object(sourcebraid, "github_json_request", side_effect=fake_request):
                with mock.patch.object(sourcebraid, "update_cache_after_delete", return_value=None):
                    result = sourcebraid.delete_clip(
                        self.config,
                        repo_path=plan.path,
                        expected_head=plan.head_sha,
                        confirm_path=plan.path,
                    )

        self.assertTrue(result["ok"])
        self.assertEqual(result["commit_sha"], "new-commit")
        tree_payload = next(payload for method, path, payload in calls if method == "POST" and path.endswith("/git/trees"))
        self.assertEqual(tree_payload["base_tree"], plan.base_tree_sha)
        self.assertEqual(
            {entry["path"] for entry in tree_payload["tree"] if entry["sha"] is None},
            set(plan.targets),
        )
        patch_payload = next(payload for method, _path, payload in calls if method == "PATCH")
        self.assertEqual(patch_payload, {"sha": "new-commit", "force": False})
        self.assertEqual(sum(1 for method, path, _payload in calls if method == "POST" and path.endswith("/git/commits")), 1)

    def test_delete_stops_if_branch_moves_before_reference_update(self):
        plan = self.make_plan(indexed=False)
        calls = []

        def fake_request(_config, path, method="GET", payload=None):
            calls.append((method, path, payload))
            if method == "POST" and path.endswith("/git/trees"):
                return {"sha": "new-tree"}
            if method == "POST" and path.endswith("/git/commits"):
                return {"sha": "orphaned-commit"}
            if method == "GET" and "/git/ref/heads/" in path:
                return {"object": {"sha": "moved-head"}}
            raise AssertionError((method, path, payload))

        with mock.patch.object(sourcebraid, "build_delete_plan", return_value=plan):
            with mock.patch.object(sourcebraid, "github_json_request", side_effect=fake_request):
                with self.assertRaisesRegex(sourcebraid.KnowledgeError, "branch was not modified"):
                    sourcebraid.delete_clip(
                        self.config,
                        repo_path=plan.path,
                        expected_head=plan.head_sha,
                        confirm_path=plan.path,
                    )

        self.assertFalse(any(method == "PATCH" for method, _path, _payload in calls))

    def make_plan(self, head_sha="head-sha", indexed=True):
        return sourcebraid.DeletePlan(
            repo=self.config.repo_slug,
            branch=self.config.branch,
            head_sha=head_sha,
            base_tree_sha="base-tree",
            path="web-clips/2026/07/example.md",
            title="Example",
            url="https://example.com",
            indexed=indexed,
            index_path="web-clips/index.jsonl",
            targets=[
                "web-clips/2026/07/example.md",
                "web-clips/2026/07/assets/example/image.webp",
            ],
            warnings=[],
            next_index_text='{"path":"web-clips/keep.md"}\n' if indexed else None,
        )


if __name__ == "__main__":
    unittest.main()
