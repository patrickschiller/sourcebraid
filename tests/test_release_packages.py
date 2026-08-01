import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
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


class ChromePackageTests(unittest.TestCase):
    def test_build_uses_only_the_explicit_allowlist(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = {"manifest_version": 3, "name": "SourceBraid", "version": "1.2.3"}
            for relative in chrome_package.PACKAGE_FILES:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"fixture")
            (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
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
            for relative in chrome_package.PACKAGE_FILES:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"fixture")
            (root / "manifest.json").write_text(
                json.dumps({"manifest_version": 3, "name": "SourceBraid", "version": "1.0.0"}),
                encoding="utf-8",
            )
            (root / "content.js").unlink()
            (root / "content.js").symlink_to(root / "background.js")

            with self.assertRaises(chrome_package.PackageError):
                chrome_package.validated_package_files(root)


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


if __name__ == "__main__":
    unittest.main()
