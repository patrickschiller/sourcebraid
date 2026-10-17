import importlib.util
import sys
import unittest
import plistlib
import tempfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def load_validator():
    path = REPOSITORY_ROOT / "scripts" / "validate_ios_release.py"
    spec = importlib.util.spec_from_file_location("validate_ios_release", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


ios_release = load_validator()


class IOSReleaseTests(unittest.TestCase):
    def test_reader_privacy_reasons_are_exact_and_extension_stays_restricted(self):
        manifest = plistlib.loads((REPOSITORY_ROOT / ios_release.APP_PRIVACY).read_bytes())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "PrivacyInfo.xcprivacy"
            path.write_bytes(plistlib.dumps(manifest))
            errors = []
            ios_release.validate_privacy_manifest(path, errors, archive_reader=True)
            self.assertEqual(errors, [])
            ios_release.validate_privacy_manifest(path, errors, archive_reader=False)
            self.assertTrue(errors, "Share Extension must not silently inherit reader APIs")
            for entry in manifest["NSPrivacyAccessedAPITypes"]:
                if entry["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryFileTimestamp":
                    entry["NSPrivacyAccessedAPITypeReasons"] = ["DDA9.1"]
            path.write_bytes(plistlib.dumps(manifest))
            errors = []
            ios_release.validate_privacy_manifest(path, errors, archive_reader=True)
            self.assertTrue(errors, "Unreviewed file metadata purposes must be rejected")

    def test_app_store_candidate_is_internally_consistent(self):
        report = ios_release.validate_source(REPOSITORY_ROOT)

        self.assertEqual(report.marketing_version, "1.1.1")
        self.assertEqual(report.build_number, "12")
        self.assertEqual(
            report.icon_sha256,
            "3adcbd818e547ae7da3f5df26111631aa86f39549d07480bbce959f760731b93",
        )


if __name__ == "__main__":
    unittest.main()
