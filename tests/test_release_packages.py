import importlib.util
import json
import re
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


chrome_package = load_module(
    "build_chrome_package",
    REPOSITORY_ROOT / "scripts" / "build_chrome_package.py",
)
plugin_package = load_module(
    "build_plugin_package",
    REPOSITORY_ROOT / "scripts" / "build_plugin_package.py",
)
setup_package = load_module(
    "build_setup_package",
    REPOSITORY_ROOT / "scripts" / "build_setup_package.py",
)


class ChromePackageTests(unittest.TestCase):
    def test_build_uses_only_the_explicit_allowlist(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            extension_root = root.joinpath(*chrome_package.EXTENSION_DIRECTORY.parts)
            manifest = {"manifest_version": 3, "name": "SourceBraid", "version": "1.2.3"}
            for relative in chrome_package.PACKAGE_FILES:
                target = extension_root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"fixture")
            (extension_root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            (root / "web-clips" / "private.md").parent.mkdir(parents=True)
            (root / "web-clips" / "private.md").write_text("secret", encoding="utf-8")
            output = root / "dist" / "sourcebraid.zip"

            version, digest = chrome_package.build_package(root, output)

            self.assertEqual(version, "1.2.3")
            self.assertEqual(len(digest), 64)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(sorted(archive.namelist()), sorted(chrome_package.PACKAGE_FILES))
                self.assertNotIn("web-clips/private.md", archive.namelist())

    def test_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            extension_root = root.joinpath(*chrome_package.EXTENSION_DIRECTORY.parts)
            for relative in chrome_package.PACKAGE_FILES:
                target = extension_root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"fixture")
            (extension_root / "manifest.json").write_text(
                json.dumps({"manifest_version": 3, "name": "SourceBraid", "version": "1.0.0"}),
                encoding="utf-8",
            )
            (extension_root / "content.js").unlink()
            (extension_root / "content.js").symlink_to(extension_root / "background.js")

            with self.assertRaises(chrome_package.PackageError):
                chrome_package.validated_package_files(root)

    def test_bundled_pdf_support_matches_the_canonical_files(self):
        extension_root = REPOSITORY_ROOT.joinpath(*chrome_package.EXTENSION_DIRECTORY.parts)

        for relative in chrome_package.PDF_SUPPORT_FILES:
            with self.subTest(path=relative):
                self.assertEqual(
                    (extension_root / relative).read_bytes(),
                    (REPOSITORY_ROOT / relative).read_bytes(),
                )


class ChromeStoreReadinessTests(unittest.TestCase):
    def test_permissions_are_explicit_and_match_the_single_purpose(self):
        manifest = json.loads(
            (REPOSITORY_ROOT / "chrome-extension" / "sourcebraid" / "manifest.json").read_text()
        )
        self.assertEqual(
            set(manifest["permissions"]),
            {"activeTab", "scripting", "storage"},
        )
        self.assertEqual(
            set(manifest["host_permissions"]),
            {"http://*/*", "https://*/*", "file:///*"},
        )
        self.assertNotIn("<all_urls>", manifest["host_permissions"])

    def test_first_capture_disclosure_and_privacy_link_are_packaged(self):
        extension_root = REPOSITORY_ROOT / "chrome-extension" / "sourcebraid"
        popup_html = (extension_root / "popup.html").read_text(encoding="utf-8")
        popup_js = (extension_root / "popup.js").read_text(encoding="utf-8")

        self.assertIn('id="data-disclosure"', popup_html)
        self.assertIn('id="data-consent" type="checkbox"', popup_html)
        self.assertIn("PRIVACY.md", popup_html)
        self.assertIn('const DATA_DISCLOSURE_VERSION = "1";', popup_js)
        self.assertIn("await ensureDataDisclosureAccepted();", popup_js)

    def test_store_assets_have_exact_required_dimensions(self):
        expected = {
            "sourcebraid-chrome-capture-1280x800.png": (1280, 800),
            "sourcebraid-private-archive-1280x800.png": (1280, 800),
            "sourcebraid-promo-440x280.png": (440, 280),
        }
        asset_root = REPOSITORY_ROOT / "chrome-extension" / "store-assets"
        for filename, dimensions in expected.items():
            with self.subTest(filename=filename):
                data = (asset_root / filename).read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(struct.unpack(">II", data[16:24]), dimensions)

    def test_store_short_descriptions_fit_chrome_limit(self):
        listing = (
            REPOSITORY_ROOT / "chrome-extension" / "STORE_LISTING.md"
        ).read_text(encoding="utf-8")
        descriptions = re.findall(r"Short description: `([^`]+)`", listing)
        self.assertEqual(len(descriptions), 2)
        for description in descriptions:
            self.assertLessEqual(len(description), 132)


class PluginPackageTests(unittest.TestCase):
    def test_public_package_removes_local_mcp_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = root / ".codex-plugin" / "plugin.json"
            manifest_path.parent.mkdir(parents=True)
            manifest_path.write_text(
                json.dumps(
                    {
                        "name": "sourcebraid",
                        "version": "1.0.0",
                        "description": "fixture",
                        "skills": "./skills/",
                        "mcpServers": "./.mcp.json",
                    }
                ),
                encoding="utf-8",
            )
            for relative in plugin_package.PLUGIN_FILES:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"fixture")
            (root / ".mcp.json").write_text('{"private": true}', encoding="utf-8")
            output = root / "sourcebraid-plugin.zip"

            version, _digest = plugin_package.build_package(root, output)

            self.assertEqual(version, "1.0.0")
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read(".codex-plugin/plugin.json"))
                self.assertNotIn("mcpServers", manifest)
                self.assertNotIn(".mcp.json", archive.namelist())
                self.assertIn("scripts/sourcebraid.py", archive.namelist())


class SetupPackageTests(unittest.TestCase):
    def test_build_is_standalone_deterministic_and_allowlisted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            chrome_manifest = root / "chrome-extension" / "sourcebraid" / "manifest.json"
            plugin_manifest = root / "codex-plugin" / "sourcebraid" / ".codex-plugin" / "plugin.json"
            for manifest in (chrome_manifest, plugin_manifest):
                manifest.parent.mkdir(parents=True, exist_ok=True)
                manifest.write_text(json.dumps({"version": "1.2.3"}), encoding="utf-8")

            setup_script = root.joinpath(*setup_package.SETUP_SCRIPT.parts)
            setup_script.parent.mkdir(parents=True, exist_ok=True)
            setup_script.write_bytes(
                (REPOSITORY_ROOT / "scripts" / "setup_github.py").read_bytes()
            )
            expected = {}
            for relative in setup_package.SUPPORT_FILES:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                content = f"fixture:{relative}".encode()
                target.write_bytes(content)
                expected[relative] = content
            private = root / "web-clips" / "private.md"
            private.parent.mkdir(parents=True)
            private.write_text("do-not-package-this-secret", encoding="utf-8")

            first = root / "dist" / "first.py"
            second = root / "dist" / "second.py"
            version, first_digest = setup_package.build_package(root, first)
            _version, second_digest = setup_package.build_package(root, second)

            self.assertEqual(version, "1.2.3")
            self.assertEqual(first_digest, second_digest)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertNotIn(b"do-not-package-this-secret", first.read_bytes())

            standalone = load_module("standalone_setup_fixture", first)
            with tempfile.TemporaryDirectory() as empty_directory:
                files = standalone.local_support_files(Path(empty_directory), "web-clips")
            for relative, content in expected.items():
                self.assertEqual(files[relative], content)


class ReleaseVersionTests(unittest.TestCase):
    def test_customer_facing_versions_match_ios_release(self):
        chrome = json.loads(
            (REPOSITORY_ROOT / "chrome-extension" / "sourcebraid" / "manifest.json").read_text()
        )
        plugin = json.loads(
            (
                REPOSITORY_ROOT
                / "codex-plugin"
                / "sourcebraid"
                / ".codex-plugin"
                / "plugin.json"
            ).read_text()
        )
        project = (REPOSITORY_ROOT / "ios" / "SourceBraid.xcodeproj" / "project.pbxproj").read_text()
        mcp = (
            REPOSITORY_ROOT / "codex-plugin" / "sourcebraid" / "scripts" / "sourcebraid_mcp.py"
        ).read_text()

        ios_versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", project))
        mcp_version = re.search(r'^SERVER_VERSION = "([^"]+)"$', mcp, re.MULTILINE)
        self.assertEqual(chrome["version"], "1.0.1")
        self.assertEqual(plugin["version"], chrome["version"])
        self.assertEqual(ios_versions, {chrome["version"]})
        self.assertIsNotNone(mcp_version)
        self.assertEqual(mcp_version.group(1), chrome["version"])

    def test_repo_marketplace_exposes_the_versioned_plugin(self):
        marketplace_path = REPOSITORY_ROOT / ".agents" / "plugins" / "marketplace.json"
        marketplace = json.loads(marketplace_path.read_text(encoding="utf-8"))

        self.assertEqual(marketplace["name"], "sourcebraid")
        self.assertEqual(marketplace["interface"]["displayName"], "SourceBraid")
        self.assertEqual(len(marketplace["plugins"]), 1)
        entry = marketplace["plugins"][0]
        self.assertEqual(entry["name"], "sourcebraid")
        self.assertEqual(
            entry["source"],
            {"source": "local", "path": "./codex-plugin/sourcebraid"},
        )
        self.assertEqual(
            entry["policy"],
            {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
        )
        self.assertEqual(entry["category"], "Productivity")
        self.assertTrue((REPOSITORY_ROOT / entry["source"]["path"]).is_dir())


if __name__ == "__main__":
    unittest.main()
