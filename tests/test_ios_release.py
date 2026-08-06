import importlib.util
import sys
import unittest
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
    def test_app_store_candidate_is_internally_consistent(self):
        report = ios_release.validate_source(REPOSITORY_ROOT)

        self.assertEqual(report.marketing_version, "1.0.0")
        self.assertEqual(report.build_number, "6")
        self.assertEqual(
            report.icon_sha256,
            "3adcbd818e547ae7da3f5df26111631aa86f39549d07480bbce959f760731b93",
        )


if __name__ == "__main__":
    unittest.main()
