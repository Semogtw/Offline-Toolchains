from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "validate_goanime_hosted_packages.py"


def load_module():
    spec = importlib.util.spec_from_file_location("hosted_manifest", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HostedPackageManifestTest(unittest.TestCase):
    def test_accepts_sorted_exact_public_versions(self) -> None:
        module = load_module()

        packages = module.parse_manifest(
            """# Public hosted packages only\nalpha=1.2.3\nbeta_pkg=2.0.0-dev.1+4\n"""
        )

        self.assertEqual(
            [(item.name, item.version) for item in packages],
            [("alpha", "1.2.3"), ("beta_pkg", "2.0.0-dev.1+4")],
        )

    def test_rejects_unsorted_packages(self) -> None:
        module = load_module()

        with self.assertRaisesRegex(ValueError, "sorted"):
            module.parse_manifest("beta=1.0.0\nalpha=1.0.0\n")

    def test_rejects_duplicate_packages(self) -> None:
        module = load_module()

        with self.assertRaisesRegex(ValueError, "duplicate"):
            module.parse_manifest("alpha=1.0.0\nalpha=1.0.1\n")

    def test_rejects_constraints_and_metadata(self) -> None:
        module = load_module()

        invalid_lines = (
            "alpha=^1.0.0\n",
            "alpha=>=1.0.0\n",
            "alpha=https://example.invalid/package.tar.gz\n",
            "alpha=1.0.0 sha256:deadbeef\n",
            "Alpha=1.0.0\n",
        )
        for content in invalid_lines:
            with self.subTest(content=content):
                with self.assertRaises(ValueError):
                    module.parse_manifest(content)


if __name__ == "__main__":
    unittest.main()
