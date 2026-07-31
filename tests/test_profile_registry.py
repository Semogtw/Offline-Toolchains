from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.lib.profile_registry import expand_profile, load_profiles


class ProfileRegistryTests(unittest.TestCase):
    def test_repository_profiles_expand_in_activation_order(self) -> None:
        registry = load_profiles(Path("profiles"))
        self.assertEqual(
            expand_profile("zapzap-full", registry),
            ["android-base", "jdk21", "zapzap-pure", "zapzap-android"],
        )
        self.assertEqual(
            expand_profile("goanime-full", registry),
            ["android-base", "goanime-analysis", "goanime-android"],
        )

    def test_cycle_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = {
                "kind": "concrete", "project": None, "packages": ["x"],
                "activation_order": 1, "lock_mode": "not-applicable",
                "lock_inputs": [], "doctor_checks": [], "platform": "linux",
                "architecture": "x86_64",
            }
            a = dict(base, name="a", packages=["a"], requires=["b"])
            b = dict(base, name="b", packages=["b"], requires=["a"])
            (root / "a.json").write_text(json.dumps(a))
            (root / "b.json").write_text(json.dumps(b))
            with self.assertRaisesRegex(ValueError, "cycle"):
                load_profiles(root)

    def test_unknown_dependency_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = {
                "name": "a", "kind": "concrete", "project": None,
                "packages": ["a"], "requires": ["missing"],
                "activation_order": 1, "lock_mode": "not-applicable",
                "lock_inputs": [], "doctor_checks": [], "platform": "linux",
                "architecture": "x86_64",
            }
            (root / "a.json").write_text(json.dumps(profile))
            with self.assertRaisesRegex(ValueError, "unknown dependency"):
                load_profiles(root)


if __name__ == "__main__":
    unittest.main()
