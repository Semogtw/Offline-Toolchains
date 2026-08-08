from __future__ import annotations

import json
import pathlib
import tempfile
import unittest

from scripts.resolve_codex_toolchain_trigger import TriggerError
from scripts.resolve_codex_toolchain_trigger import resolve_trigger


class ResolveCodexToolchainTriggerTests(unittest.TestCase):
    def write_request(self, payload: dict[str, object]) -> pathlib.Path:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        path = pathlib.Path(temp_dir.name) / "request.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_accepts_exact_allowlisted_core_sha(self) -> None:
        request = self.write_request(
            {
                "schema_version": 1,
                "repository": "Semogtw/codex-gemini-agents",
                "ref": "e88d8ef2dcb0a3c4bbed9425930f253494ababfd",
            }
        )
        resolved = resolve_trigger(request)
        self.assertEqual(resolved.repository, "Semogtw/codex-gemini-agents")
        self.assertEqual(
            resolved.ref, "e88d8ef2dcb0a3c4bbed9425930f253494ababfd"
        )

    def test_accepts_safe_feature_ref_for_manual_toolchain_hydration(self) -> None:
        request = self.write_request(
            {
                "schema_version": 1,
                "repository": "Semogtw/codex-gemini-agents",
                "ref": "feature/native-harness-local-tools-mcp",
            }
        )
        self.assertEqual(
            resolve_trigger(request).ref, "feature/native-harness-local-tools-mcp"
        )

    def test_rejects_non_allowlisted_repository(self) -> None:
        request = self.write_request(
            {
                "schema_version": 1,
                "repository": "someone/other-fork",
                "ref": "main",
            }
        )
        with self.assertRaisesRegex(TriggerError, "allowlisted"):
            resolve_trigger(request)

    def test_rejects_unsafe_refs(self) -> None:
        for ref in ("../main", "/main", "main/", "main ref", "", "a" * 161):
            with self.subTest(ref=ref):
                request = self.write_request(
                    {
                        "schema_version": 1,
                        "repository": "Semogtw/codex-gemini-agents",
                        "ref": ref,
                    }
                )
                with self.assertRaises(TriggerError):
                    resolve_trigger(request)

    def test_rejects_unknown_schema_or_fields(self) -> None:
        for payload in (
            {
                "schema_version": 2,
                "repository": "Semogtw/codex-gemini-agents",
                "ref": "main",
            },
            {
                "schema_version": 1,
                "repository": "Semogtw/codex-gemini-agents",
                "ref": "main",
                "token": "must-not-be-accepted",
            },
        ):
            with self.subTest(payload=payload):
                with self.assertRaises(TriggerError):
                    resolve_trigger(self.write_request(payload))


if __name__ == "__main__":
    unittest.main()
