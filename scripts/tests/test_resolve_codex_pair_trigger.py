from __future__ import annotations

import json
import pathlib
import tempfile
import unittest

from scripts.resolve_codex_pair_trigger import PairTriggerError
from scripts.resolve_codex_pair_trigger import resolve_pair_trigger


CORE_SHA = "e88d8ef2dcb0a3c4bbed9425930f253494ababfd"
WRAPPER_SHA = "0574e3a710aa58c2cb443bf7d7e7c47ff34a8d71"


class ResolveCodexPairTriggerTests(unittest.TestCase):
    def write_request(self, payload: dict[str, object]) -> pathlib.Path:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        path = pathlib.Path(temp_dir.name) / "request.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def valid_payload(self) -> dict[str, object]:
        return {
            "schema_version": 1,
            "core_repository": "Semogtw/codex-gemini-agents",
            "core_ref": CORE_SHA,
            "wrapper_repository": "Semogtw/codex-desktop-linux-gemini-",
            "wrapper_ref": WRAPPER_SHA,
        }

    def test_accepts_only_exact_allowlisted_pair(self) -> None:
        resolved = resolve_pair_trigger(self.write_request(self.valid_payload()))
        self.assertEqual(resolved.core_ref, CORE_SHA)
        self.assertEqual(resolved.wrapper_ref, WRAPPER_SHA)

    def test_rejects_branch_refs_for_reproducible_pair_builds(self) -> None:
        for field in ("core_ref", "wrapper_ref"):
            payload = self.valid_payload()
            payload[field] = "feature/linux-packaging"
            with self.subTest(field=field):
                with self.assertRaisesRegex(PairTriggerError, "40-character"):
                    resolve_pair_trigger(self.write_request(payload))

    def test_rejects_non_allowlisted_repositories(self) -> None:
        for field in ("core_repository", "wrapper_repository"):
            payload = self.valid_payload()
            payload[field] = "someone/other-fork"
            with self.subTest(field=field):
                with self.assertRaisesRegex(PairTriggerError, "allowlisted"):
                    resolve_pair_trigger(self.write_request(payload))

    def test_rejects_unknown_fields_or_schema(self) -> None:
        payload = self.valid_payload()
        payload["secret"] = "not-allowed"
        with self.assertRaises(PairTriggerError):
            resolve_pair_trigger(self.write_request(payload))
        payload = self.valid_payload()
        payload["schema_version"] = 2
        with self.assertRaises(PairTriggerError):
            resolve_pair_trigger(self.write_request(payload))


if __name__ == "__main__":
    unittest.main()
