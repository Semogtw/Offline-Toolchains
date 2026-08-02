from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "validate_goanime_gradle_modules.py"


def load_module():
    spec = importlib.util.spec_from_file_location("gradle_manifest", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GradleModuleManifestTest(unittest.TestCase):
    def test_accepts_sorted_exact_coordinates(self) -> None:
        module = load_module()
        self.assertEqual(
            module.parse_manifest(
                "a.group:alpha:1.2.3\nz.group:beta:2.0.0-RC1\n"
            ),
            ("a.group:alpha:1.2.3", "z.group:beta:2.0.0-RC1"),
        )

    def test_rejects_duplicates(self) -> None:
        module = load_module()
        with self.assertRaisesRegex(ValueError, "duplicates"):
            module.parse_manifest("a:b:1.0.0\na:b:1.0.0\n")

    def test_rejects_unsorted_coordinates(self) -> None:
        module = load_module()
        with self.assertRaisesRegex(ValueError, "sorted"):
            module.parse_manifest("z:b:1.0.0\na:b:1.0.0\n")

    def test_rejects_constraints_urls_and_classifiers(self) -> None:
        module = load_module()
        for content in (
            "a:b:+\n",
            "a:b:[1.0,2.0)\n",
            "a:b:https://example.invalid/x\n",
            "a:b:1.0.0:classifier\n",
        ):
            with self.subTest(content=content):
                with self.assertRaises(ValueError):
                    module.parse_manifest(content)


if __name__ == "__main__":
    unittest.main()
