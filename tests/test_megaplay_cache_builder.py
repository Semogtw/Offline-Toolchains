from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from tools.megaplay_cache.build_megaplay_cache import (
    build_catalog_database,
    extract_series_snapshot,
    sha256_file,
    validate_catalog_database,
)
from tools.megaplay_cache.pipeline import build_manifest, collect_page_window


class MegaPlayCacheBuilderTest(unittest.TestCase):
    def test_extracts_strong_ids_and_episode_availability(self) -> None:
        recent_row = {
            "id": "fmab-1",
            "title": "Fullmetal Alchemist: Brotherhood",
            "mal_id": 5114,
        }
        series_payload = {
            "ok": True,
            "anime": {
                "id": "fmab-1",
                "title": "Fullmetal Alchemist: Brotherhood",
                "anilist_id": 5114,
            },
            "episodes": [
                {
                    "episode_number": 1,
                    "episode_embed_id": "136197",
                    "embed_url": {
                        "sub": "https://megaplay.buzz/stream/s-2/136197/sub",
                        "dub": "https://megaplay.buzz/stream/s-2/136197/dub",
                    },
                },
                {
                    "episode_number": 2,
                    "episode_embed_id": "136198",
                    "embed_url": {
                        "sub": "https://megaplay.buzz/stream/s-2/136198/sub",
                        "dub": None,
                    },
                },
            ],
        }

        snapshot = extract_series_snapshot(recent_row, series_payload)

        self.assertIsNotNone(snapshot)
        assert snapshot is not None
        self.assertEqual(snapshot.canonical_key, "mal:5114")
        self.assertEqual(snapshot.mal_id, 5114)
        self.assertEqual(snapshot.anilist_id, 5114)
        self.assertEqual(snapshot.anikoto_series_id, "fmab-1")
        self.assertEqual(len(snapshot.episodes), 2)
        self.assertTrue(snapshot.episodes[0].sub_available)
        self.assertTrue(snapshot.episodes[0].dub_available)
        self.assertEqual(snapshot.episodes[0].episode_embed_id, "136197")
        self.assertTrue(snapshot.episodes[1].sub_available)
        self.assertFalse(snapshot.episodes[1].dub_available)

    def test_title_only_series_is_not_promoted_to_authoritative_mapping(self) -> None:
        snapshot = extract_series_snapshot(
            {"id": "ambiguous-1", "title": "The Beginning"},
            {
                "ok": True,
                "anime": {"id": "ambiguous-1", "title": "The Beginning"},
                "episodes": [
                    {
                        "episode_number": 1,
                        "episode_embed_id": "1",
                        "embed_url": {"sub": "https://example.invalid/sub"},
                    }
                ],
            },
        )

        self.assertIsNone(snapshot)

    def test_build_reuses_previous_snapshot_and_replaces_only_refreshed_series(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            previous = root / "previous.db"
            output = root / "next.db"

            first = extract_series_snapshot(
                {"id": "one", "title": "One", "mal_id": 1},
                {
                    "anime": {"id": "one", "title": "One", "mal_id": 1},
                    "episodes": [
                        {
                            "episode_number": 1,
                            "episode_embed_id": "old-1",
                            "embed_url": {"sub": "sub", "dub": None},
                        }
                    ],
                },
            )
            untouched = extract_series_snapshot(
                {"id": "two", "title": "Two", "mal_id": 2},
                {
                    "anime": {"id": "two", "title": "Two", "mal_id": 2},
                    "episodes": [
                        {
                            "episode_number": 1,
                            "episode_embed_id": "two-1",
                            "embed_url": {"sub": "sub", "dub": "dub"},
                        }
                    ],
                },
            )
            assert first is not None and untouched is not None
            build_catalog_database(previous, [first, untouched])

            refreshed = extract_series_snapshot(
                {"id": "one", "title": "One", "mal_id": 1},
                {
                    "anime": {"id": "one", "title": "One", "mal_id": 1},
                    "episodes": [
                        {
                            "episode_number": 1,
                            "episode_embed_id": "new-1",
                            "embed_url": {"sub": "sub", "dub": "dub"},
                        },
                        {
                            "episode_number": 2,
                            "episode_embed_id": "new-2",
                            "embed_url": {"sub": "sub", "dub": None},
                        },
                    ],
                },
            )
            assert refreshed is not None
            build_catalog_database(output, [refreshed], previous_database=previous)
            validate_catalog_database(output)

            with sqlite3.connect(output) as db:
                rows = db.execute(
                    "SELECT canonical_key, episode_number, episode_embed_id, "
                    "sub_available, dub_available "
                    "FROM episode_availability "
                    "ORDER BY canonical_key, episode_number"
                ).fetchall()

            self.assertEqual(
                rows,
                [
                    ("mal:1", 1, "new-1", 1, 1),
                    ("mal:1", 2, "new-2", 1, 0),
                    ("mal:2", 1, "two-1", 1, 1),
                ],
            )

    def test_database_contains_only_durable_public_routing_hints(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "catalog.db"
            snapshot = extract_series_snapshot(
                {"id": "one", "title": "One", "mal_id": 1},
                {
                    "anime": {"id": "one", "title": "One", "mal_id": 1},
                    "episodes": [
                        {
                            "episode_number": 1,
                            "episode_embed_id": "embed-1",
                            "embed_url": {
                                "sub": "https://megaplay.buzz/private/signed?token=secret"
                            },
                        }
                    ],
                },
            )
            assert snapshot is not None
            build_catalog_database(output, [snapshot])
            validate_catalog_database(output)

            data = output.read_bytes()
            self.assertNotIn(b"token=secret", data)
            self.assertNotIn(b"https://megaplay.buzz/private", data)

            with sqlite3.connect(output) as db:
                tables = {
                    row[0]
                    for row in db.execute(
                        "SELECT name FROM sqlite_master WHERE type='table'"
                    ).fetchall()
                }
            self.assertTrue(
                {"series_identity", "episode_availability", "route_health", "cache_meta"}
                <= tables
            )

    def test_backfill_starts_at_cursor_and_advances_without_revisiting_recent_pages(self) -> None:
        client = _FakeAnikotoClient()

        snapshots, stats = collect_page_window(
            client,
            per_page=1,
            start_page=7,
            page_count=2,
        )

        self.assertEqual(client.recent_pages, [7, 8])
        self.assertEqual([snapshot.mal_id for snapshot in snapshots], [7, 8])
        self.assertEqual(stats.start_page, 7)
        self.assertEqual(stats.pages, 2)
        self.assertEqual(stats.next_page, 9)
        self.assertFalse(stats.reached_end)

    def test_backfill_wraps_cursor_when_listing_ends(self) -> None:
        client = _FakeAnikotoClient(end_page=8)

        _, stats = collect_page_window(
            client,
            per_page=1,
            start_page=8,
            page_count=3,
        )

        self.assertTrue(stats.reached_end)
        self.assertEqual(stats.next_page, 1)

    def test_manifest_binds_exact_database_size_digest_and_https_asset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            database = root / "megaplay_catalog.db"
            snapshot = extract_series_snapshot(
                {"id": "one", "title": "One", "mal_id": 1},
                {
                    "anime": {"id": "one", "title": "One", "mal_id": 1},
                    "episodes": [
                        {
                            "episode_number": 1,
                            "episode_embed_id": "embed-1",
                            "embed_url": {"sub": "sub", "dub": None},
                        }
                    ],
                },
            )
            assert snapshot is not None
            build_catalog_database(database, [snapshot])

            manifest = build_manifest(
                database,
                public_base_url=(
                    "https://github.com/Semogtw/Offline-Toolchains/releases/download/"
                    "goanime-megaplay-cache-latest"
                ),
            )

            self.assertEqual(manifest["schemaVersion"], 1)
            self.assertEqual(manifest["asset"]["schemaVersion"], 1)
            self.assertEqual(manifest["asset"]["sha256"], sha256_file(database))
            self.assertEqual(manifest["asset"]["sizeBytes"], database.stat().st_size)
            self.assertTrue(manifest["asset"]["url"].startswith("https://"))
            self.assertIn(manifest["asset"]["sha256"][:16], manifest["asset"]["url"])
            json.dumps(manifest)


class _FakeAnikotoClient:
    def __init__(self, *, end_page: int | None = None) -> None:
        self.end_page = end_page
        self.recent_pages: list[int] = []

    def get_json(self, path: str, query: dict[str, object] | None = None):
        if path == "recent-anime":
            assert query is not None
            page = int(query["page"])
            self.recent_pages.append(page)
            if self.end_page is not None and page > self.end_page:
                return {"data": [], "pagination": {"has_next_page": False}}
            has_next = self.end_page is None or page < self.end_page
            return {
                "data": [{"id": f"series-{page}", "mal_id": page, "title": f"Series {page}"}],
                "pagination": {"has_next_page": has_next},
            }
        if path.startswith("series/"):
            series_id = path.split("/", 1)[1]
            number = int(series_id.split("-")[-1])
            return {
                "anime": {"id": series_id, "mal_id": number, "title": f"Series {number}"},
                "episodes": [
                    {
                        "episode_number": 1,
                        "episode_embed_id": f"embed-{number}",
                        "embed_url": {"sub": "sub", "dub": None},
                    }
                ],
            }
        raise AssertionError(path)


if __name__ == "__main__":
    unittest.main()
