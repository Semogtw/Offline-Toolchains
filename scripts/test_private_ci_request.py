#!/usr/bin/env python3
"""Unit tests for private_ci_request.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from private_ci_request import PROJECTS, RequestValidationError, normalize_request


class NormalizeRequestTests(unittest.TestCase):
    def test_default_mappings_are_fixed(self) -> None:
        for project, config in PROJECTS.items():
            with self.subTest(project=project):
                normalized = normalize_request({"project": project})
                self.assertEqual(normalized["project"], project)
                self.assertEqual(normalized["repository"], config["repository"])
                self.assertEqual(normalized["ref"], config["default_ref"])
                self.assertEqual(normalized["default_ref"], config["default_ref"])

    def test_accepts_safe_branch_tag_and_sha_refs(self) -> None:
        refs = [
            "main",
            "development/android-build-recovery",
            "release-v1.2.3",
            "refs/tags/v1.0.0",
            "0123456789abcdef0123456789abcdef01234567",
        ]
        for ref in refs:
            with self.subTest(ref=ref):
                normalized = normalize_request({"project": "zapzap", "ref": ref})
                self.assertEqual(normalized["ref"], ref)

    def test_rejects_arbitrary_projects(self) -> None:
        for project in ["", "owner/repo", "offline-toolchains", 123, None]:
            with self.subTest(project=project):
                with self.assertRaises(RequestValidationError):
                    normalize_request({"project": project})

    def test_rejects_unknown_payload_fields(self) -> None:
        with self.assertRaises(RequestValidationError):
            normalize_request(
                {
                    "project": "goanime",
                    "ref": "main",
                    "repository": "attacker/repo",
                }
            )

    def test_rejects_unsafe_refs(self) -> None:
        refs = [
            " feature",
            "feature ",
            "-danger",
            ".hidden",
            "feature//nested",
            "feature/../main",
            "feature@{1}",
            "feature\\nested",
            "feature.lock",
            "feature/",
            "feature.",
            "feature~1",
            "feature^2",
            "feature:evil",
            "feature?evil",
            "feature*evil",
            "feature[evil",
            "",
            "a" * 201,
            123,
            None,
        ]
        for ref in refs:
            with self.subTest(ref=ref):
                payload = {"project": "semogsite", "ref": ref}
                if ref == "":
                    self.assertEqual(
                        normalize_request(payload)["ref"],
                        PROJECTS["semogsite"]["default_ref"],
                    )
                else:
                    with self.assertRaises(RequestValidationError):
                        normalize_request(payload)

    def test_rejects_non_object_request(self) -> None:
        for payload in [[], "goanime", None]:
            with self.subTest(payload=payload):
                with self.assertRaises(RequestValidationError):
                    normalize_request(payload)


class CliTests(unittest.TestCase):
    def test_cli_prints_compact_normalized_json(self) -> None:
        script = Path(__file__).resolve().parent / "private_ci_request.py"
        with tempfile.TemporaryDirectory() as temp_dir:
            request_path = Path(temp_dir) / "request.json"
            request_path.write_text(
                json.dumps({"project": "goanime", "ref": "main"}),
                encoding="utf-8",
            )
            result = subprocess.run(
                [sys.executable, str(script), str(request_path)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {
                "default_ref": "main",
                "project": "goanime",
                "ref": "main",
                "repository": "Semogtw/goanime-mobile",
            },
        )

    def test_cli_rejects_invalid_json(self) -> None:
        script = Path(__file__).resolve().parent / "private_ci_request.py"
        with tempfile.TemporaryDirectory() as temp_dir:
            request_path = Path(temp_dir) / "request.json"
            request_path.write_text("{", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(script), str(request_path)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 2)
        self.assertIn("request file is not valid JSON", result.stderr)


if __name__ == "__main__":
    unittest.main()
