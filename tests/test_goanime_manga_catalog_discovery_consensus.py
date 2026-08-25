import importlib.util
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "goanime_manga_catalog_discovery_consensus.py"
spec = importlib.util.spec_from_file_location(
    "goanime_manga_catalog_discovery_consensus", MODULE_PATH
)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class MangaCatalogDiscoveryConsensusTest(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 8, 25, 3, 0, tzinfo=timezone.utc)

    def _document(
        self,
        uid: str,
        *,
        source: str = "ptbr.arthurscan",
        manga_id: str = "manga-1",
        title: str = "Solo Leveling",
        kind: str = "imageSequence",
        verified_at: datetime | None = None,
        readable: bool = True,
    ) -> dict[str, object]:
        verified = (verified_at or (self.now - timedelta(minutes=5))).isoformat().replace(
            "+00:00", "Z"
        )
        return {
            "name": (
                "projects/test/databases/(default)/documents/users/"
                f"{uid}/mangaCatalogDiscoveries/doc"
            ),
            "fields": {
                "schemaVersion": {"integerValue": "1"},
                "sourceId": {"stringValue": source},
                "mangaId": {"stringValue": manga_id},
                "title": {"stringValue": title},
                "normalizedTitle": {"stringValue": title.lower()},
                "providerTitle": {"stringValue": title},
                "contentKinds": {"stringValue": kind},
                "sampleChapterId": {"stringValue": "chapter-1"},
                "verifiedAt": {"stringValue": verified},
                "readabilityVerified": {"booleanValue": readable},
                "verificationSource": {
                    "stringValue": "mangaReadableSourceDiscovery"
                },
            },
        }

    def test_two_distinct_reporters_promote_occurrence_and_kind(self) -> None:
        result = module.build_consensus(
            [self._document("uid-a"), self._document("uid-b")], now=self.now
        )
        self.assertEqual(result["candidateCount"], 1)
        candidate = result["candidates"][0]
        self.assertEqual(candidate["sourceId"], "ptbr.arthurscan")
        self.assertEqual(candidate["mangaId"], "manga-1")
        self.assertEqual(candidate["contentKinds"], ["imageSequence"])
        self.assertEqual(candidate["reporterCount"], 2)

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

    def test_mixed_kinds_only_promote_kind_with_independent_quorum(self) -> None:
        result = module.build_consensus(
            [
                self._document("uid-a", kind="imageSequence"),
                self._document("uid-b", kind="pdfDocument"),
                self._document("uid-c", kind="pdfDocument"),
            ],
            now=self.now,
        )
        self.assertEqual(result["candidateCount"], 1)
        self.assertEqual(result["candidates"][0]["contentKinds"], ["pdfDocument"])

    def test_stale_unknown_and_unreadable_reports_are_rejected(self) -> None:
        result = module.build_consensus(
            [
                self._document("uid-a", verified_at=self.now - timedelta(days=15)),
                self._document("uid-b", source="ptbr.unknown"),
                self._document("uid-c", readable=False),
            ],
            now=self.now,
        )
        self.assertEqual(result["acceptedReportCount"], 0)
        self.assertEqual(result["candidateCount"], 0)


if __name__ == "__main__":
    unittest.main()
