from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.lib.artifact_contract import load_and_validate_manifest, sha256_file


class BuildArtifactSetTests(unittest.TestCase):
    def test_builds_split_contract_and_spdx(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "jdk21"
            out = Path(directory) / "out"
            (root / "jdk/bin").mkdir(parents=True)
            java = root / "jdk/bin/java"
            java.write_text("#!/bin/sh\necho openjdk version 21 >&2\n")
            java.chmod(0o755)
            (root / "activate.sh").write_text("#!/bin/sh\n")
            (root / "activate.sh").chmod(0o755)
            software = Path(directory) / "software.json"
            software.write_text(json.dumps([{"name": "Temurin", "version": "21", "source": "https://adoptium.net", "license": "GPL-2.0-with-classpath-exception"}]))
            subprocess.run([
                "python3", "scripts/build_artifact_set.py", "--profile", "jdk21", "--package", "jdk21",
                "--root", str(root), "--out", str(out), "--lock-mode", "not-applicable",
                "--lock-fingerprint", "0" * 64, "--builder-fingerprint", "1" * 64,
                "--workflow", "test", "--workflow-commit", "2" * 40, "--run-id", "7",
                "--software", str(software), "--part-size", "32",
            ], check=True, capture_output=True, text=True)
            manifest = load_and_validate_manifest(out / "artifact-set.json")
            self.assertGreater(len(manifest["parts"]), 1)
            self.assertEqual(manifest["set_fingerprint"], manifest["set_fingerprint"].lower())
            self.assertTrue(manifest["artifact_set_id"].startswith("jdk21-" + manifest["set_fingerprint"][:16]))
            self.assertTrue((out / "SBOM.spdx.json").is_file())
            self.assertTrue((root / "artifact_contract.py").is_file())
            environment = os.environ.copy()
            environment.pop("PYTHONPATH", None)
            doctor = subprocess.run(
                [str(root / "doctor.sh"), "--manifest", str(out / "artifact-set.json"), "--root", str(root), "--json"],
                cwd=Path(directory),
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(doctor.returncode, 0, doctor.stderr + doctor.stdout)
            self.assertEqual(json.loads(doctor.stdout)["status"], "ready")
            for part in manifest["parts"]:
                self.assertEqual(sha256_file(out / part["name"]), part["sha256"])
            self.assertNotIn(str(Path(directory)), (out / "SHA256SUMS.parts").read_text())


if __name__ == "__main__":
    unittest.main()
