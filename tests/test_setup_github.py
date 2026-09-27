import contextlib
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "setup_github",
    REPOSITORY_ROOT / "scripts" / "setup_github.py",
)
setup_github = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = setup_github
SPEC.loader.exec_module(setup_github)


class FakeGitHubCLI:
    def __init__(self, responses=None):
        self.responses = responses or {}
        self.calls = []
        self.authenticated = False

    def auth_status(self):
        self.authenticated = True

    def api(self, method, endpoint, payload=None, *, allow_not_found=False):
        self.calls.append((method, endpoint, payload, allow_not_found))
        return self.responses.get((method, endpoint))


class SetupGitHubTests(unittest.TestCase):
    def test_parse_repository_requires_owner_and_name(self):
        repository = setup_github.parse_repository("octocat/sourcebraid-private")
        self.assertEqual(repository.slug, "octocat/sourcebraid-private")
        with self.assertRaises(Exception):
            setup_github.parse_repository("sourcebraid-private")

    def test_public_repository_is_rejected(self):
        repository = setup_github.RepositoryName("octocat", "archive")
        client = FakeGitHubCLI({("GET", "/repos/octocat/archive"): {"private": False}})
        with self.assertRaises(setup_github.SetupError):
            setup_github.ensure_repository(client, repository, dry_run=False)

    def test_setup_paths_match_capture_and_plugin_boundaries(self):
        self.assertEqual(setup_github.normalize_root_folder("notes/clips"), "notes/clips")
        for value in ("../secret", "web-clips/../secret", ".github", "notes/.GIT", "/web-clips", "web-clips//notes", "web-clips\\secret", "web-clips\x00"):
            with self.subTest(value=value), self.assertRaises(Exception):
                setup_github.normalize_root_folder(value)
        for value in ("owner/repo?ref=other", "owner/repo#fragment", "owner/repo\\other", "owner/.."):
            with self.subTest(value=value), self.assertRaises(Exception):
                setup_github.parse_repository(value)

    def test_default_repository_uses_authenticated_account(self):
        client = FakeGitHubCLI({("GET", "/user"): {"login": "octocat"}})

        repository, viewer_login = setup_github.resolve_repository(client, None)

        self.assertEqual(repository.slug, "octocat/sourcebraid-private")
        self.assertEqual(viewer_login, "octocat")

    def test_main_dry_run_needs_no_repository_argument(self):
        responses = {
            ("GET", "/user"): {"login": "octocat"},
            ("GET", "/repos/octocat/sourcebraid-private"): {
                "private": True,
                "default_branch": "main",
            },
        }
        client = FakeGitHubCLI(responses)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in setup_github.SUPPORT_FILES:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture", encoding="utf-8")
            config_path = root / "sourcebraid-config.json"
            output = io.StringIO()
            with mock.patch.object(setup_github, "GitHubCLI", return_value=client):
                with contextlib.redirect_stdout(output):
                    result = setup_github.main(
                        [
                            "--dry-run",
                            "--repository-root",
                            str(root),
                            "--config-output",
                            str(config_path),
                        ]
                    )

        self.assertEqual(result, 0)
        self.assertTrue(client.authenticated)
        self.assertFalse(config_path.exists())
        self.assertIn(
            "repository: https://github.com/octocat/sourcebraid-private",
            output.getvalue(),
        )

    def test_existing_files_are_preserved_by_default(self):
        repository = setup_github.RepositoryName("octocat", "archive")
        existing_endpoint = "/repos/octocat/archive/contents/scripts/existing.py?ref=main"
        client = FakeGitHubCLI({("GET", existing_endpoint): {"sha": "abc123"}})

        created, updated, skipped = setup_github.upload_support_files(
            client,
            repository,
            "main",
            {"scripts/existing.py": b"new", "scripts/new.py": b"new"},
            dry_run=False,
            update_existing=False,
        )

        self.assertEqual(created, ["scripts/new.py"])
        self.assertEqual(updated, [])
        self.assertEqual(skipped, ["scripts/existing.py"])
        put_paths = [call[1] for call in client.calls if call[0] == "PUT"]
        self.assertEqual(put_paths, ["/repos/octocat/archive/contents/scripts/new.py"])

    def test_support_file_allowlist_never_reads_private_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in setup_github.SUPPORT_FILES:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture", encoding="utf-8")
            private = root / "web-clips" / "private.md"
            private.parent.mkdir(parents=True)
            private.write_text("secret", encoding="utf-8")

            files = setup_github.local_support_files(root, "web-clips")

            self.assertEqual(
                sorted(files),
                sorted((*setup_github.SUPPORT_FILES, "web-clips/.gitkeep")),
            )
            self.assertNotIn("web-clips/private.md", files)

    def test_embedded_support_files_take_precedence_in_standalone_build(self):
        original = setup_github.EMBEDDED_SUPPORT_FILES
        setup_github.EMBEDDED_SUPPORT_FILES = {
            relative: setup_github.base64.b64encode(f"embedded:{relative}".encode()).decode()
            for relative in setup_github.SUPPORT_FILES
        }
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for relative in setup_github.SUPPORT_FILES:
                    target = root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text("local", encoding="utf-8")

                files = setup_github.local_support_files(root, "web-clips")
        finally:
            setup_github.EMBEDDED_SUPPORT_FILES = original

        for relative in setup_github.SUPPORT_FILES:
            self.assertEqual(files[relative], f"embedded:{relative}".encode())

    def test_plugin_config_is_token_free_and_preserved_by_default(self):
        repository = setup_github.RepositoryName("octocat", "sourcebraid-private")
        payload = setup_github.plugin_config(repository, "main", "web-clips")
        self.assertNotIn("token", payload)

        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "sourcebraid-config.json"
            path, status = setup_github.write_plugin_config(
                target,
                payload,
                dry_run=False,
                overwrite=False,
            )
            self.assertEqual(path, target)
            self.assertEqual(status, "created")
            self.assertEqual(json.loads(target.read_text(encoding="utf-8")), payload)
            self.assertEqual(stat.S_IMODE(os.stat(target).st_mode), 0o600)

            target.write_text('{"owner": "keep-me"}\n', encoding="utf-8")
            _path, status = setup_github.write_plugin_config(
                target,
                payload,
                dry_run=False,
                overwrite=False,
            )
            self.assertEqual(status, "preserved")
            self.assertEqual(json.loads(target.read_text(encoding="utf-8")), {"owner": "keep-me"})


if __name__ == "__main__":
    unittest.main()
