from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.verify_goanime_source_receipt import verify_receipt


class VerifyGoAnimeSourceReceiptTest(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 8, 2, 23, 0, tzinfo=timezone.utc)

    def valid_receipt(self) -> dict[str, object]:
        return {
            "schema_version": 1,
            "run_id": 30739999999,
            "run_url": "https://github.com/Semogtw/Offline-Toolchains/actions/runs/30739999999",
            "workflow_head_sha": "a" * 40,
            "workflow_event": "workflow_run",
            "recorded_at_utc": "2026-08-02T22:58:00Z",
            "artifacts": [
                {
                    "artifact_id": 9000000001,
                    "name": "private-source-goanime-ref-manifest",
                    "size_bytes": 1200,
                    "expired": False,
                    "created_at": "2026-08-02T22:57:00Z",
                    "expires_at": "2026-08-03T22:57:00Z",
                },
                {
                    "artifact_id": 9000000002,
                    "name": "private-source-goanime-ref-part-000",
                    "size_bytes": 400000000,
                    "expired": False,
                    "created_at": "2026-08-02T22:57:00Z",
                    "expires_at": "2026-08-03T22:57:00Z",
                },
                {
                    "artifact_id": 9000000003,
                    "name": "private-source-goanime-ref-part-001",
                    "size_bytes": 123456,
                    "expired": False,
                    "created_at": "2026-08-02T22:57:00Z",
                    "expires_at": "2026-08-03T22:57:00Z",
                },
            ],
        }

    def write_receipt(self, payload: dict[str, object]) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "receipt.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_accepts_one_manifest_and_contiguous_parts(self) -> None:
        result = verify_receipt(self.write_receipt(self.valid_receipt()), now=self.now)

        self.assertEqual(result["run_id"], 30739999999)
        self.assertEqual(result["manifest_artifact_id"], 9000000001)
        self.assertEqual(result["part_artifact_ids"], [9000000002, 9000000003])

    def test_rejects_expired_artifact(self) -> None:
        payload = self.valid_receipt()
        payload["artifacts"][1]["expired"] = True  # type: ignore[index]

        with self.assertRaisesRegex(ValueError, "expired"):
            verify_receipt(self.write_receipt(payload), now=self.now)

    def test_rejects_past_expiry_timestamp(self) -> None:
        payload = self.valid_receipt()
        payload["artifacts"][1]["expires_at"] = "2026-08-02T22:00:00Z"  # type: ignore[index]

        with self.assertRaisesRegex(ValueError, "expires_at"):
            verify_receipt(self.write_receipt(payload), now=self.now)

    def test_rejects_missing_part_number(self) -> None:
        payload = self.valid_receipt()
        payload["artifacts"][2]["name"] = "private-source-goanime-ref-part-002"  # type: ignore[index]

        with self.assertRaisesRegex(ValueError, "contiguous"):
            verify_receipt(self.write_receipt(payload), now=self.now)

    def test_rejects_duplicate_artifact_id(self) -> None:
        payload = self.valid_receipt()
        payload["artifacts"][2]["artifact_id"] = 9000000002  # type: ignore[index]

        with self.assertRaisesRegex(ValueError, "duplicate artifact_id"):
            verify_receipt(self.write_receipt(payload), now=self.now)

    def test_rejects_non_goanime_artifact(self) -> None:
        payload = self.valid_receipt()
        payload["artifacts"][1]["name"] = "private-source-semogsite-ref-part-000"  # type: ignore[index]

        with self.assertRaisesRegex(ValueError, "GoAnime"):
            verify_receipt(self.write_receipt(payload), now=self.now)

    def test_rejects_multiple_manifests(self) -> None:
        payload = self.valid_receipt()
        payload["artifacts"].append(  # type: ignore[union-attr]
            {
                "artifact_id": 9000000004,
                "name": "private-source-goanime-ref-manifest",
                "size_bytes": 1200,
                "expired": False,
                "created_at": "2026-08-02T22:57:00Z",
                "expires_at": "2026-08-03T22:57:00Z",
            }
        )

        with self.assertRaisesRegex(ValueError, "exactly one manifest"):
            verify_receipt(self.write_receipt(payload), now=self.now)


if __name__ == "__main__":
    unittest.main()
