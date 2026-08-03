from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.verify_goanime_toolchain_receipt import verify_receipt


NOW = datetime(2026, 8, 3, 0, 0, tzinfo=timezone.utc)
RUN_ID = 30799999999


def artifact(
    artifact_id: int,
    name: str,
    *,
    expires: str = "2026-08-04T00:00:00Z",
) -> dict[str, object]:
    return {
        "artifact_id": artifact_id,
        "name": name,
        "size_bytes": 1024,
        "expired": False,
        "created_at": "2026-08-03T00:00:00Z",
        "expires_at": expires,
    }


def receipt() -> dict[str, object]:
    return {
        "schema_version": 1,
        "run_id": RUN_ID,
        "run_url": (
            "https://github.com/Semogtw/Offline-Toolchains/actions/runs/"
            f"{RUN_ID}"
        ),
        "workflow_head_sha": "a" * 40,
        "workflow_event": "push",
        "recorded_at_utc": "2026-08-03T00:10:00Z",
        "artifacts": [
            artifact(1, "goanime-flutter-cache-linux-x64-manifest"),
            artifact(2, "goanime-flutter-cache-linux-x64-part-00"),
            artifact(3, "goanime-flutter-cache-linux-x64-part-01"),
        ],
    }


class VerifyGoAnimeToolchainReceiptTest(unittest.TestCase):
    def write(self, payload: object) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "receipt.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_accepts_manifest_and_contiguous_parts(self) -> None:
        result = verify_receipt(self.write(receipt()), now=NOW)
        self.assertEqual(result["run_id"], RUN_ID)
        self.assertEqual(result["manifest_artifact_id"], 1)
        self.assertEqual(result["part_artifact_ids"], [2, 3])

    def test_rejects_missing_manifest(self) -> None:
        payload = receipt()
        artifacts = list(payload["artifacts"])
        payload["artifacts"] = artifacts[1:]
        with self.assertRaisesRegex(ValueError, "exactly one manifest"):
            verify_receipt(self.write(payload), now=NOW)

    def test_rejects_non_contiguous_parts(self) -> None:
        payload = receipt()
        artifacts = list(payload["artifacts"])
        artifacts[-1] = dict(artifacts[-1])
        artifacts[-1]["name"] = "goanime-flutter-cache-linux-x64-part-02"
        payload["artifacts"] = artifacts
        with self.assertRaisesRegex(ValueError, "contiguous from 00"):
            verify_receipt(self.write(payload), now=NOW)

    def test_rejects_duplicate_ids(self) -> None:
        payload = receipt()
        artifacts = list(payload["artifacts"])
        artifacts[-1] = dict(artifacts[-1])
        artifacts[-1]["artifact_id"] = 2
        payload["artifacts"] = artifacts
        with self.assertRaisesRegex(ValueError, "duplicate artifact_id"):
            verify_receipt(self.write(payload), now=NOW)

    def test_rejects_expired_part(self) -> None:
        payload = receipt()
        artifacts = list(payload["artifacts"])
        artifacts[-1] = dict(artifacts[-1])
        artifacts[-1]["expires_at"] = "2026-08-02T23:59:59Z"
        payload["artifacts"] = artifacts
        with self.assertRaisesRegex(ValueError, "not in the future"):
            verify_receipt(self.write(payload), now=NOW)

    def test_rejects_wrong_run_url(self) -> None:
        payload = receipt()
        payload["run_url"] = "https://example.invalid/run"
        with self.assertRaisesRegex(ValueError, "run_url"):
            verify_receipt(self.write(payload), now=NOW)

    def test_accepts_manual_dispatch(self) -> None:
        payload = receipt()
        payload["workflow_event"] = "workflow_dispatch"
        verify_receipt(self.write(payload), now=NOW)


if __name__ == "__main__":
    unittest.main()
