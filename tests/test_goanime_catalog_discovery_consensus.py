from __future__ import annotations

import importlib.util
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "goanime_catalog_discovery_consensus.py"
spec = importlib.util.spec_from_file_location("goanime_catalog_discovery_consensus", MODULE_PATH)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class CatalogDiscoveryConsensusTest(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 8, 23, 21, 50, tzinfo=timezone.utc)

    def _document(
        self,
        uid: str,
        *,
        mal_id: int = 123,
        provider: str = "goyabu",
        title: str = "Example Anime",
        verified_at: datetime | None = None,
        playback_verified: bool = True,
    ) -> dict[str, object]:
        verified = (verified_at or (self.now - timedelta(minutes=5))).isoformat().replace(
            "+00:00", "Z"
        )
        return {
            "name": (
                "projects/test/databases/(default)/documents/users/"
                f"{uid}/catalogDiscoveries/doc"
            ),
            "fields": {
                "schemaVersion": {"integerValue": "1"},
                "malId": {"integerValue": str(mal_id)},
                "title": {"stringValue": title},
                "normalizedTitle": {"stringValue": title.lower()},
                "providerId": {"stringValue": provider},
                "providerName": {"stringValue": provider.title()},
                "providerTitle": {"stringValue": title},
                "hasSub": {"booleanValue": True},
                "hasDub": {"booleanValue": False},
                "verifiedAt": {"stringValue": verified},
                "playbackVerified": {"booleanValue": playback_verified},
                "verificationSource": {
                    "stringValue": "dynamicAvailabilityCache"
                },
            },
        }

    def test_one_reporter_is_not_consensus(self) -> None:
        result = module.build_consensus([self._document("uid-a")], now=self.now)
        self.assertEqual(result["acceptedReportCount"], 1)
        self.assertEqual(result["candidateCount"], 0)

    def test_two_distinct_reporters_create_one_candidate(self) -> None:
        result = module.build_consensus(
            [self._document("uid-a"), self._document("uid-b")],
            now=self.now,
        )
        self.assertEqual(result["candidateCount"], 1)
        candidate = result["candidates"][0]
        self.assertEqual(candidate["reporterCount"], 2)
        self.assertEqual(candidate["malId"], 123)
        self.assertEqual(candidate["providerId"], "goyabu")

    def test_same_reporter_does_not_count_twice(self) -> None:
        result = module.build_consensus(
            [
                self._document("uid-a", verified_at=self.now - timedelta(minutes=10)),
                self._document("uid-a", verified_at=self.now - timedelta(minutes=1)),
            ],
            now=self.now,
        )
        self.assertEqual(result["acceptedReportCount"], 2)
        self.assertEqual(result["candidateCount"], 0)

    def test_stale_and_unverified_reports_are_rejected(self) -> None:
        result = module.build_consensus(
            [
                self._document(
                    "uid-a", verified_at=self.now - timedelta(days=15)
                ),
                self._document("uid-b", playback_verified=False),
            ],
            now=self.now,
        )
        self.assertEqual(result["acceptedReportCount"], 0)
        self.assertEqual(result["candidateCount"], 0)

    def test_unknown_provider_is_rejected(self) -> None:
        result = module.build_consensus(
            [
                self._document("uid-a", provider="unknown"),
                self._document("uid-b", provider="unknown"),
            ],
            now=self.now,
        )
        self.assertEqual(result["acceptedReportCount"], 0)
        self.assertEqual(result["candidateCount"], 0)


if __name__ == "__main__":
    unittest.main()
