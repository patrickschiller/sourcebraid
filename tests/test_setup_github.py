import importlib.util
import sys
import tempfile
import unittest
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


if __name__ == "__main__":
    unittest.main()
