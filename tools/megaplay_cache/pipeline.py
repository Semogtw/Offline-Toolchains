from __future__ import annotations

import dataclasses
import datetime as dt
import json
import sqlite3
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Mapping, Protocol

from .build_megaplay_cache import (
    AnikotoFatalError,
    SeriesSnapshot,
    _extract_recent_rows,
    _has_next_page,
    _series_id_from_recent,
    extract_series_snapshot,
    iso_utc,
    sha256_file,
    utc_now,
    validate_catalog_database,
)


class JsonClient(Protocol):
    def get_json(
        self,
        path: str,
        query: Mapping[str, Any] | None = None,
    ) -> Mapping[str, Any]: ...


@dataclasses.dataclass
class PageWindowStats:
    start_page: int
    pages: int = 0
    rows_seen: int = 0
    series_requested: int = 0
    mapped_series: int = 0
    unmapped_series: int = 0
    failed_series: int = 0
    episodes: int = 0
    next_page: int = 1
    reached_end: bool = False

    def to_json(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


def collect_page_window(
    client: JsonClient,
    *,
    start_page: int,
    page_count: int,
    per_page: int,
) -> tuple[list[SeriesSnapshot], PageWindowStats]:
    if start_page <= 0:
        raise ValueError("start_page must be positive")
    if page_count <= 0:
        raise ValueError("page_count must be positive")
    if per_page <= 0 or per_page > 500:
        raise ValueError("per_page must be between 1 and 500")

    stats = PageWindowStats(start_page=start_page, next_page=start_page)
    snapshots: dict[str, SeriesSnapshot] = {}

    for page in range(start_page, start_page + page_count):
        listing = client.get_json(
            "recent-anime",
            {"page": page, "per_page": per_page},
        )
        rows = _extract_recent_rows(listing)
        stats.pages += 1
        stats.rows_seen += len(rows)
        if not rows:
            stats.reached_end = True
            stats.next_page = 1
            break

        for row in rows:
            series_id = _series_id_from_recent(row)
            if series_id is None:
                stats.unmapped_series += 1
                continue
            stats.series_requested += 1
            try:
                payload = client.get_json(f"series/{series_id}")
            except AnikotoFatalError:
                raise
            except Exception as error:
                print(
                    f"warning: failed series {series_id}: "
                    f"{type(error).__name__}: {error}",
                    file=sys.stderr,
                )
                stats.failed_series += 1
                continue

            snapshot = extract_series_snapshot(row, payload)
            if snapshot is None:
                stats.unmapped_series += 1
                continue
            snapshots[snapshot.canonical_key] = snapshot
            stats.mapped_series += 1
            stats.episodes += len(snapshot.episodes)

        if not _has_next_page(listing, page, len(rows), per_page):
            stats.reached_end = True
            stats.next_page = 1
            break
        stats.next_page = page + 1

    return list(snapshots.values()), stats


def read_cache_meta(database: Path | str, key: str) -> str | None:
    path = Path(database)
    if not path.exists():
        return None
    validate_catalog_database(path)
    with sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True) as db:
        row = db.execute(
            "SELECT value FROM cache_meta WHERE key = ? LIMIT 1",
            (key,),
        ).fetchone()
    return None if row is None else str(row[0])


def write_cache_meta(database: Path | str, key: str, value: str) -> None:
    path = Path(database)
    validate_catalog_database(path)
    with sqlite3.connect(path) as db:
        db.execute(
            "INSERT OR REPLACE INTO cache_meta(key, value) VALUES(?, ?)",
            (key, value),
        )
        db.commit()
    validate_catalog_database(path)


def build_manifest(
    database: Path | str,
    *,
    public_base_url: str,
    generated_at: dt.datetime | None = None,
) -> dict[str, Any]:
    path = Path(database)
    validate_catalog_database(path)

    base = _validated_public_base_url(public_base_url)
    digest = sha256_file(path)
    filename = f"megaplay_catalog_{digest[:16]}.db"
    generated = generated_at
    if generated is None:
        persisted = read_cache_meta(path, "generatedAt")
        generated = _parse_timestamp(persisted) or utc_now()

    with sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True) as db:
        series_count = int(db.execute("SELECT COUNT(*) FROM series_identity").fetchone()[0])
        episode_count = int(
            db.execute("SELECT COUNT(*) FROM episode_availability").fetchone()[0]
        )

    return {
        "schemaVersion": 1,
        "generatedAt": iso_utc(generated),
        "asset": {
            "url": f"{base}/{filename}",
            "sha256": digest,
            "sizeBytes": path.stat().st_size,
            "schemaVersion": 1,
        },
        "catalog": {
            "seriesCount": series_count,
            "episodeCount": episode_count,
        },
    }


def write_manifest(
    database: Path | str,
    output: Path | str,
    *,
    public_base_url: str,
) -> dict[str, Any]:
    manifest = build_manifest(database, public_base_url=public_base_url)
    destination = Path(output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def _validated_public_base_url(value: str) -> str:
    text = value.strip().rstrip("/")
    uri = urllib.parse.urlparse(text)
    if (
        uri.scheme.lower() != "https"
        or not uri.hostname
        or uri.username is not None
        or uri.password is not None
        or uri.query
        or uri.fragment
    ):
        raise ValueError("public_base_url must be an absolute credential-free HTTPS URL")
    return text


def _parse_timestamp(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)
