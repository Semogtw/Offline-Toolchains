from __future__ import annotations

import copy
import unittest

from scripts.lib.artifact_contract import compute_fingerprint, validate_manifest


def valid_manifest() -> dict:
    return {
        "schema_version": 2,
        "artifact_set_id": "goanime-analysis-" + "a" * 16 + "-123",
        "set_fingerprint": "a" * 64,
        "profile": "goanime-analysis",
        "package": "goanime-analysis",
        "lock_mode": "private-exact",
        "lock_fingerprint": "1" * 64,
        "builder_fingerprint": "2" * 64,
        "workflow": "Build exact toolchain",
        "workflow_commit": "3" * 40,
        "run_id": 123,
        "created_at": "2026-07-31T00:00:00Z",
        "expires_at": "2026-08-01T00:00:00Z",
        "platform": "linux",
        "architecture": "x86_64",
        "archive": {"name": "goanime-analysis.tar.zst", "sha256": "4" * 64, "size": 10},
        "parts": [{"index": 0, "name": "goanime-analysis.part-00", "artifact_name": "goanime-analysis-aaaaaaaaaaaaaaaa-123-part-00", "sha256": "5" * 64, "size": 10}],
        "requires": [],
        "activation_script": "activate.sh",
        "doctor_script": "doctor.sh",
        "software_inventory": "SBOM.spdx.json",
        "compatibility": {"minimum_restore_version": 2},
    }


class ArtifactContractTests(unittest.TestCase):
    def test_valid_manifest(self) -> None:
        self.assertEqual(validate_manifest(valid_manifest()), [])

    def test_rejects_wrong_architecture_and_oversized_part(self) -> None:
        document = valid_manifest()
        document["architecture"] = "aarch64"
        document["parts"][0]["size"] = 400 * 1024 * 1024 + 1
        errors = validate_manifest(document)
        self.assertTrue(any("architecture" in error for error in errors))
        self.assertTrue(any("400 MiB" in error for error in errors))

    def test_rejects_unsafe_paths_and_duplicate_parts(self) -> None:
        document = valid_manifest()
        document["archive"]["name"] = "../escape.tar.zst"
        duplicate = copy.deepcopy(document["parts"][0])
        duplicate["index"] = 1
        document["parts"].append(duplicate)
        errors = validate_manifest(document)
        self.assertTrue(any("archive.name" in error for error in errors))
        self.assertTrue(any("duplicate part name" in error for error in errors))

    def test_fingerprint_is_length_delimited(self) -> None:
        self.assertNotEqual(compute_fingerprint([b"ab", b"c"]), compute_fingerprint([b"a", b"bc"]))
        self.assertEqual(compute_fingerprint([b"x"]), compute_fingerprint([b"x"]))


if __name__ == "__main__":
    unittest.main()
