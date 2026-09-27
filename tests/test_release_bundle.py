import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import build_release as release
import build_review_fixture as review
sys.path.pop(0)

SPEC = importlib.util.spec_from_file_location(
    "sourcebraid_review_under_test", ROOT / "codex-plugin/sourcebraid/scripts/sourcebraid.py",
)
sourcebraid = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = sourcebraid
SPEC.loader.exec_module(sourcebraid)


class ReleaseBundleTests(unittest.TestCase):
    def test_bundle_is_reproducible_and_contains_only_public_allowlisted_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "bundle"
            manifest = release.build_release(ROOT, output, reproducible=True)
            self.assertEqual(release.verify_bundle(output), manifest)
            self.assertEqual(set(manifest["files"]), {
                *release.KIT_FILES, *release.artifact_names(manifest["version"]).values(), "START_HERE.md",
            })
            self.assertFalse(any(name.startswith(("website/", "web-clips/", ".git/")) for name in manifest["files"]))
            # Re-running on a verified bundle is supported, with the same bytes.
            before = (output / release.CHECKSUMS_NAME).read_bytes()
            release.build_release(ROOT, output)
            self.assertEqual((output / release.CHECKSUMS_NAME).read_bytes(), before)

    def test_changed_payload_and_unexpected_files_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "bundle"
            release.build_release(ROOT, output)
            target = output / "PRIVACY.md"
            original = target.read_bytes()
            target.write_bytes(original + b"tampered")
            with self.assertRaisesRegex(release.ReleaseError, "checksum mismatch"):
                release.verify_bundle(output)
            target.write_bytes(original)
            extra = output / "private-token.txt"
            extra.write_text("private local file")
            with self.assertRaisesRegex(release.ReleaseError, "unexpected files"):
                release.build_release(ROOT, output)
            self.assertEqual(extra.read_text(), "private local file")

    def test_symlinked_parent_directory_cannot_enter_allowlist(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "private").mkdir()
            (root / "private" / "file.txt").write_text("private")
            (root / "public").symlink_to(root / "private", target_is_directory=True)
            with self.assertRaisesRegex(release.ReleaseError, "symlink"):
                release.safe_source(root, "public/file.txt")
            for builder, error in (
                (release.chrome, release.chrome.PackageError),
                (release.plugin, release.plugin.PluginPackageError),
                (release.setup, release.setup.SetupPackageError),
                (release.mcp, release.mcp.MCPPackageError),
            ):
                with self.subTest(builder=builder.__name__):
                    with self.assertRaisesRegex(error, "symlink"):
                        builder.package_source(root, PurePosixPath("public/file.txt"))

    def test_secret_diagnostic_never_echoes_the_secret(self):
        secret = b"github_pat_" + b"x" * 50
        with self.assertRaises(release.ReleaseError) as caught:
            release.scan_content("listing.md", secret)
        self.assertNotIn(secret.decode(), str(caught.exception))
        self.assertIn("GitHub credential", str(caught.exception))
        release.scan_content("popup.html", b'placeholder="github_pat_..."')

    def test_fixture_metadata_points_to_matching_synthetic_markdown(self):
        files = review.fixture_files()
        self.assertEqual(len(files), 6)
        self.assertEqual(sum(name.endswith(".md") for name in files), 3)
        for path, content in files.items():
            if path.endswith(".jsonl"):
                item = json.loads(content)
                self.assertEqual(item["source"], "synthetic")
                self.assertTrue(item["url"].startswith("https://example.com/sourcebraid-review/"))
                self.assertEqual(Path(path).stem, sourcebraid.url_hash(item["url"])[:2])
                self.assertIn(item["title"].encode(), files[item["path"]])
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "fixture.zip"
            first = review.build_package(output)
            self.assertEqual(first, review.build_package(output))
            with zipfile.ZipFile(output) as archive:
                self.assertEqual({name: archive.read(name) for name in archive.namelist()}, files)

    def test_mcp_package_is_deterministic_and_excludes_runtime_secrets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for source, _ in release.mcp.MCP_FILES:
                path = root / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"synthetic fixture: {source}\n")
            package = {"name": "sourcebraid-chatgpt-mcp", "version": "1.2.3"}
            (root / "chatgpt-mcp/package.json").write_text(json.dumps(package))
            (root / "chatgpt-mcp/package-lock.json").write_text(json.dumps({
                **package, "lockfileVersion": 3, "packages": {"": package},
            }))
            (root / "docs/CHATGPT_MCP_DEPLOYMENT.md").write_text(
                "[Privacy](../PRIVACY.md)\n[Submission](../marketing/OPENAI_MCP_SUBMISSION.md)\n",
            )
            for forbidden in ("chatgpt-mcp/.dev.vars", "chatgpt-mcp/.env", "chatgpt-mcp/node_modules/private/token.txt", "website/private.txt", "web-clips/private.md"):
                path = root / forbidden
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("do-not-publish-this-private-data")
            first = root / "first.zip"
            second = root / "second.zip"
            first_version, first_hash = release.mcp.build_package(root, first)
            second_version, second_hash = release.mcp.build_package(root, second)
            self.assertEqual((first_version, first_hash), (second_version, second_hash))
            self.assertEqual(first_version, "1.2.3")
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(set(archive.namelist()), {name for _, name in release.mcp.MCP_FILES})
                deployment = archive.read("DEPLOYMENT.md").decode()
                self.assertIn("https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md", deployment)
                self.assertIn("https://github.com/patrickschiller/sourcebraid/blob/main/marketing/OPENAI_MCP_SUBMISSION.md", deployment)
                self.assertNotIn("](../", deployment)
                for name in archive.namelist():
                    self.assertNotIn(b"do-not-publish-this-private-data", archive.read(name))
            (root / "chatgpt-mcp/package-lock.json").write_text(json.dumps({"version": "1.0.0"}))
            with self.assertRaisesRegex(release.mcp.MCPPackageError, "lockfile version"):
                release.mcp.build_package(root, root / "mismatched.zip")
            self.assertFalse((root / "mismatched.zip").exists())


if __name__ == "__main__":
    unittest.main()
