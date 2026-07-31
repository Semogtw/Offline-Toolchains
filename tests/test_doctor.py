from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.test_artifact_contract import valid_manifest


class DoctorTests(unittest.TestCase):
    def test_ready_and_partial_json_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "bin/tool"
            binary.parent.mkdir()
            binary.write_text("#!/bin/sh\necho tool 1.0\n")
            binary.chmod(0o755)
            manifest = valid_manifest()
            manifest["doctor_checks"] = [{"type": "executable", "path": "bin/tool"}]
            path = root / "artifact-set.json"
            path.write_text(json.dumps(manifest))
            ready = subprocess.run(["python3", "scripts/doctor.py", "--manifest", str(path), "--root", str(root), "--json"], capture_output=True, text=True)
            self.assertEqual(ready.returncode, 0)
            self.assertEqual(json.loads(ready.stdout)["status"], "ready")
            binary.unlink()
            partial = subprocess.run(["python3", "scripts/doctor.py", "--manifest", str(path), "--root", str(root), "--json"], capture_output=True, text=True)
            self.assertEqual(partial.returncode, 1)
            self.assertEqual(json.loads(partial.stdout)["status"], "partial")


if __name__ == "__main__":
    unittest.main()
