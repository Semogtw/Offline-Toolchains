from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

from scripts.assemble_artifact import safe_extract_zip


class AssembleArtifactTests(unittest.TestCase):
    def _build(self, directory: Path) -> tuple[Path, dict]:
        root = directory / "jdk21"
        out = directory / "built"
        (root / "jdk/bin").mkdir(parents=True)
        java = root / "jdk/bin/java"
        java.write_text("#!/bin/sh\necho 21\n")
        java.chmod(0o755)
        (root / "activate.sh").write_text("#!/bin/sh\n")
        (root / "activate.sh").chmod(0o755)
        subprocess.run([
            "python3", "scripts/build_artifact_set.py", "--profile", "jdk21", "--package", "jdk21",
            "--root", str(root), "--out", str(out), "--lock-mode", "not-applicable",
            "--lock-fingerprint", "0" * 64, "--builder-fingerprint", "1" * 64,
            "--workflow", "test", "--workflow-commit", "2" * 40, "--run-id", "9", "--part-size", "64",
        ], check=True, capture_output=True, text=True)
        return out, json.loads((out / "artifact-set.json").read_text())

    def test_assembles_download_zips_and_detects_tamper(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            built, manifest = self._build(directory)
            downloads = directory / "downloads"
            downloads.mkdir()
            with zipfile.ZipFile(downloads / "manifest.zip", "w") as handle:
                for name in ("artifact-set.json", "PARTS.txt", "SHA256SUMS.parts", "SBOM.spdx.json"):
                    handle.write(built / name, name)
            for part in manifest["parts"]:
                with zipfile.ZipFile(downloads / f"{part['index']}.zip", "w") as handle:
                    handle.write(built / part["name"], part["name"])
            output = directory / "assembled.tar.zst"
            completed = subprocess.run(["python3", "scripts/assemble_artifact.py", str(downloads), str(output)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(output.read_bytes(), (built / manifest["archive"]["name"]).read_bytes())
            output.unlink()
            first = manifest["parts"][0]
            with zipfile.ZipFile(downloads / "0.zip", "w") as handle:
                tampered = directory / first["name"]
                tampered.write_bytes(b"tampered")
                handle.write(tampered, first["name"])
            failed = subprocess.run(["python3", "scripts/assemble_artifact.py", str(downloads), str(output)], capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("mismatch", failed.stdout)

    def test_rejects_zip_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            archive = directory / "evil.zip"
            with zipfile.ZipFile(archive, "w") as handle:
                handle.writestr("../escape", "bad")
            with self.assertRaisesRegex(ValueError, "unsafe ZIP"):
                safe_extract_zip(archive, directory / "out")


if __name__ == "__main__":
    unittest.main()
