#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable, Iterator, Mapping, Sequence

SCHEMA_VERSION = 1
DEFAULT_BASE_URL = "https://anikotoapi.site"
DEFAULT_REQUEST_INTERVAL_SECONDS = 2.1
DEFAULT_INCREMENTAL_PAGES = 5
DEFAULT_PER_PAGE = 100
DEFAULT_EVIDENCE_TTL = dt.timedelta(hours=36)
USER_AGENT = "GoAnime-Offline-Toolchains/1.0 (+MegaPlay cache)"


class AnikotoFatalError(RuntimeError):
    pass


@dataclasses.dataclass(frozen=True)
class EpisodeSnapshot:
    episode_number: int
    sub_available: bool
    dub_available: bool
    episode_embed_id: str | None


@dataclasses.dataclass(frozen=True)
class SeriesSnapshot:
    canonical_key: str
    mal_id: int | None
    anilist_id: int | None
    anikoto_series_id: str
    normalized_title: str
    match_confidence: float
    episodes: tuple[EpisodeSnapshot, ...]


@dataclasses.dataclass
class CollectionStats:
    pages: int = 0
    rows_seen: int = 0
    series_requested: int = 0
    mapped_series: int = 0
    unmapped_series: int = 0
    failed_series: int = 0
    episodes: int = 0

    def to_json(self) -> dict[str, int]:
        return dataclasses.asdict(self)


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso_utc(value: dt.datetime) -> str:
    value = value.astimezone(dt.timezone.utc)
    return value.isoformat().replace("+00:00", "Z")


def normalize_title(value: Any) -> str:
    text = str(value or "").strip().casefold()
    decomposed = unicodedata.normalize("NFKD", text)
    asciiish = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    normalized = " ".join(
        "".join(ch if ch.isalnum() else " " for ch in asciiish).split()
    )
    return normalized


def _positive_int(value: Any) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value if value > 0 else None
    if isinstance(value, float):
        if value.is_integer() and value > 0:
            return int(value)
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        number = float(text)
    except ValueError:
        return None
    if number <= 0 or not number.is_integer():
        return None
    return int(number)


def _clean_id(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None


def _mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _first_value(objects: Sequence[Mapping[str, Any]], keys: Sequence[str]) -> Any:
    wanted = {key.casefold() for key in keys}
    for obj in objects:
        for key, value in obj.items():
            if key.casefold() in wanted and value is not None:
                return value
    return None


def _recursive_value(value: Any, keys: Sequence[str], depth: int = 0) -> Any:
    if depth > 4:
        return None
    wanted = {key.casefold() for key in keys}
    if isinstance(value, Mapping):
        for key, child in value.items():
            if key.casefold() in wanted and child is not None:
                return child
        for child in value.values():
            found = _recursive_value(child, keys, depth + 1)
            if found is not None:
                return found
    return None


def _extract_episode_list(payload: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    candidates: list[Any] = [payload.get("episodes")]
    for container_name in ("data", "anime", "series"):
        container = _mapping(payload.get(container_name))
        candidates.append(container.get("episodes"))
    for candidate in candidates:
        if isinstance(candidate, list):
            return [item for item in candidate if isinstance(item, Mapping)]
    return []


def _extract_embed_map(episode: Mapping[str, Any]) -> Mapping[str, Any]:
    for key in ("embed_url", "embed_urls", "embedUrl", "embedUrls"):
        candidate = episode.get(key)
        if isinstance(candidate, Mapping):
            return candidate
    return {}


def _nonempty_urlish(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _extract_embed_id_from_url(value: Any) -> str | None:
    if not _nonempty_urlish(value):
        return None
    try:
        uri = urllib.parse.urlparse(str(value).strip())
    except ValueError:
        return None
    segments = [segment for segment in uri.path.split("/") if segment]
    if len(segments) >= 3 and segments[-3] == "s-2":
        return _clean_id(segments[-2])
    query = urllib.parse.parse_qs(uri.query)
    for key in ("ep", "episode", "episode_id"):
        values = query.get(key)
        if values:
            return _clean_id(values[0])
    return None


def _bool_hint(episode: Mapping[str, Any], keys: Sequence[str]) -> bool | None:
    value = _first_value([episode], keys)
    if isinstance(value, bool):
        return value
    if isinstance(value, int) and value in (0, 1):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().casefold()
        if lowered in {"true", "yes", "1", "available"}:
            return True
        if lowered in {"false", "no", "0", "missing", "unavailable"}:
            return False
    return None


def _extract_episode_snapshot(episode: Mapping[str, Any]) -> EpisodeSnapshot | None:
    number = _positive_int(
        _first_value(
            [episode],
            ("episode_number", "episodeNumber", "number", "episode", "ep"),
        )
    )
    if number is None:
        return None

    embeds = _extract_embed_map(episode)
    sub_value = _first_value([embeds], ("sub", "subbed", "subtitle"))
    dub_value = _first_value([embeds], ("dub", "dubbed"))
    sub_hint = _bool_hint(episode, ("has_sub", "hasSub", "sub_available", "subAvailable"))
    dub_hint = _bool_hint(episode, ("has_dub", "hasDub", "dub_available", "dubAvailable"))
    sub_available = _nonempty_urlish(sub_value) if sub_value is not None else bool(sub_hint)
    dub_available = _nonempty_urlish(dub_value) if dub_value is not None else bool(dub_hint)

    embed_id = _clean_id(
        _first_value(
            [episode],
            ("episode_embed_id", "episodeEmbedId", "embed_id", "embedId"),
        )
    )
    if embed_id is None:
        embed_id = _extract_embed_id_from_url(sub_value) or _extract_embed_id_from_url(dub_value)

    return EpisodeSnapshot(
        episode_number=number,
        sub_available=sub_available,
        dub_available=dub_available,
        episode_embed_id=embed_id,
    )


def extract_series_snapshot(
    recent_row: Mapping[str, Any],
    series_payload: Mapping[str, Any],
) -> SeriesSnapshot | None:
    anime = _mapping(series_payload.get("anime"))
    data = _mapping(series_payload.get("data"))
    data_anime = _mapping(data.get("anime"))
    objects = (anime, data_anime, recent_row)

    mal_id = _positive_int(
        _first_value(
            objects,
            ("mal_id", "malId", "myanimelist_id", "myAnimeListId", "mal"),
        )
    )
    anilist_id = _positive_int(
        _first_value(
            objects,
            ("anilist_id", "anilistId", "aniListId", "anilist"),
        )
    )
    if mal_id is None:
        mal_id = _positive_int(
            _recursive_value(anime or data_anime or recent_row, ("mal_id", "malId"))
        )
    if anilist_id is None:
        anilist_id = _positive_int(
            _recursive_value(
                anime or data_anime or recent_row,
                ("anilist_id", "anilistId", "aniListId"),
            )
        )

    # Title-only matching is deliberately not authoritative. The collector may
    # learn stronger mappings later, but must not make an ambiguous title a
    # globally cached availability fact.
    if mal_id is None and anilist_id is None:
        return None

    canonical_key = f"mal:{mal_id}" if mal_id is not None else f"anilist:{anilist_id}"
    series_id = _clean_id(
        _first_value(
            objects,
            ("id", "series_id", "seriesId", "anime_id", "animeId", "slug"),
        )
    )
    if series_id is None:
        return None

    title = _first_value(
        objects,
        ("title", "name", "english_title", "title_english", "titleEnglish"),
    )
    normalized_title = normalize_title(title)
    if not normalized_title:
        normalized_title = canonical_key

    episodes_by_number: dict[int, EpisodeSnapshot] = {}
    for raw_episode in _extract_episode_list(series_payload):
        episode = _extract_episode_snapshot(raw_episode)
        if episode is not None:
            episodes_by_number[episode.episode_number] = episode

    return SeriesSnapshot(
        canonical_key=canonical_key,
        mal_id=mal_id,
        anilist_id=anilist_id,
        anikoto_series_id=series_id,
        normalized_title=normalized_title,
        match_confidence=1.0,
        episodes=tuple(episodes_by_number[number] for number in sorted(episodes_by_number)),
    )


def _create_schema(db: sqlite3.Connection) -> None:
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS series_identity (
          canonical_key TEXT PRIMARY KEY,
          mal_id INTEGER,
          anilist_id INTEGER,
          anikoto_series_id TEXT,
          normalized_title TEXT NOT NULL,
          match_confidence REAL,
          remote_updated_at TEXT,
          local_updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS series_identity_anikoto_idx
          ON series_identity(anikoto_series_id)
          WHERE anikoto_series_id IS NOT NULL;

        CREATE TABLE IF NOT EXISTS episode_availability (
          canonical_key TEXT NOT NULL,
          episode_number INTEGER NOT NULL,
          sub_available INTEGER,
          dub_available INTEGER,
          episode_embed_id TEXT,
          provenance TEXT NOT NULL,
          verified_at TEXT,
          expires_at TEXT,
          PRIMARY KEY (canonical_key, episode_number)
        );
        CREATE INDEX IF NOT EXISTS episode_availability_expiry_idx
          ON episode_availability(expires_at);

        CREATE TABLE IF NOT EXISTS route_health (
          canonical_key TEXT NOT NULL,
          language TEXT NOT NULL,
          route_type TEXT NOT NULL,
          last_success_at TEXT,
          last_failure_at TEXT,
          failure_kind TEXT,
          consecutive_failures INTEGER NOT NULL DEFAULT 0,
          retry_after TEXT,
          PRIMARY KEY (canonical_key, language, route_type)
        );
        CREATE INDEX IF NOT EXISTS route_health_retry_idx
          ON route_health(retry_after);

        CREATE TABLE IF NOT EXISTS cache_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        """
    )
    db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")


def build_catalog_database(
    output: Path | str,
    snapshots: Iterable[SeriesSnapshot],
    *,
    previous_database: Path | str | None = None,
    generated_at: dt.datetime | None = None,
) -> None:
    output_path = Path(output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    if previous_database is not None and Path(previous_database).exists():
        validate_catalog_database(Path(previous_database))
        shutil.copy2(previous_database, output_path)

    generated = (generated_at or utc_now()).astimezone(dt.timezone.utc)
    generated_text = iso_utc(generated)
    expires_text = iso_utc(generated + DEFAULT_EVIDENCE_TTL)

    with sqlite3.connect(output_path) as db:
        _create_schema(db)
        db.execute("PRAGMA foreign_keys = ON")
        db.execute("DELETE FROM route_health")
        for snapshot in snapshots:
            old_keys = [
                row[0]
                for row in db.execute(
                    "SELECT canonical_key FROM series_identity "
                    "WHERE anikoto_series_id = ? AND canonical_key <> ?",
                    (snapshot.anikoto_series_id, snapshot.canonical_key),
                ).fetchall()
            ]
            for old_key in old_keys:
                db.execute(
                    "DELETE FROM episode_availability WHERE canonical_key = ?",
                    (old_key,),
                )
                db.execute(
                    "DELETE FROM series_identity WHERE canonical_key = ?",
                    (old_key,),
                )

            db.execute(
                """
                INSERT INTO series_identity (
                  canonical_key, mal_id, anilist_id, anikoto_series_id,
                  normalized_title, match_confidence, remote_updated_at,
                  local_updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(canonical_key) DO UPDATE SET
                  mal_id = excluded.mal_id,
                  anilist_id = excluded.anilist_id,
                  anikoto_series_id = excluded.anikoto_series_id,
                  normalized_title = excluded.normalized_title,
                  match_confidence = excluded.match_confidence,
                  remote_updated_at = excluded.remote_updated_at,
                  local_updated_at = excluded.local_updated_at
                """,
                (
                    snapshot.canonical_key,
                    snapshot.mal_id,
                    snapshot.anilist_id,
                    snapshot.anikoto_series_id,
                    snapshot.normalized_title,
                    snapshot.match_confidence,
                    generated_text,
                    generated_text,
                ),
            )
            db.execute(
                "DELETE FROM episode_availability WHERE canonical_key = ?",
                (snapshot.canonical_key,),
            )
            db.executemany(
                """
                INSERT INTO episode_availability (
                  canonical_key, episode_number, sub_available, dub_available,
                  episode_embed_id, provenance, verified_at, expires_at
                ) VALUES (?, ?, ?, ?, ?, 'remoteCache', ?, ?)
                """,
                [
                    (
                        snapshot.canonical_key,
                        episode.episode_number,
                        1 if episode.sub_available else 0,
                        1 if episode.dub_available else 0,
                        episode.episode_embed_id,
                        generated_text,
                        expires_text,
                    )
                    for episode in snapshot.episodes
                ],
            )

        db.execute(
            "INSERT OR REPLACE INTO cache_meta(key, value) VALUES('schemaVersion', ?)",
            (str(SCHEMA_VERSION),),
        )
        db.execute(
            "INSERT OR REPLACE INTO cache_meta(key, value) VALUES('generatedAt', ?)",
            (generated_text,),
        )
        db.commit()

    validate_catalog_database(output_path)


def validate_catalog_database(path: Path | str) -> None:
    database_path = Path(path)
    if not database_path.is_file() or database_path.stat().st_size <= 0:
        raise ValueError(f"MegaPlay catalog is missing or empty: {database_path}")

    uri = f"file:{database_path.resolve()}?mode=ro"
    with sqlite3.connect(uri, uri=True) as db:
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("MegaPlay catalog integrity_check failed")
        if db.execute("PRAGMA user_version").fetchone()[0] != SCHEMA_VERSION:
            raise ValueError("MegaPlay catalog schema version is unsupported")

        required_columns = {
            "series_identity": {
                "canonical_key",
                "mal_id",
                "anilist_id",
                "anikoto_series_id",
                "normalized_title",
                "match_confidence",
                "remote_updated_at",
                "local_updated_at",
            },
            "episode_availability": {
                "canonical_key",
                "episode_number",
                "sub_available",
                "dub_available",
                "episode_embed_id",
                "provenance",
                "verified_at",
                "expires_at",
            },
            "route_health": {
                "canonical_key",
                "language",
                "route_type",
                "last_success_at",
                "last_failure_at",
                "failure_kind",
                "consecutive_failures",
                "retry_after",
            },
            "cache_meta": {"key", "value"},
        }
        for table, expected in required_columns.items():
            actual = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
            if not expected <= actual:
                missing = sorted(expected - actual)
                raise ValueError(f"MegaPlay catalog {table} missing columns: {missing}")

        invalid = db.execute(
            "SELECT COUNT(*) FROM episode_availability "
            "WHERE episode_number <= 0 "
            "OR sub_available NOT IN (0, 1) "
            "OR dub_available NOT IN (0, 1) "
            "OR provenance <> 'remoteCache'"
        ).fetchone()[0]
        if invalid:
            raise ValueError("MegaPlay catalog contains invalid episode rows")

        invalid_keys = db.execute(
            "SELECT COUNT(*) FROM series_identity "
            "WHERE canonical_key NOT GLOB 'mal:[0-9]*' "
            "AND canonical_key NOT GLOB 'anilist:[0-9]*'"
        ).fetchone()[0]
        if invalid_keys:
            raise ValueError("MegaPlay catalog contains non-canonical identities")

        if db.execute("SELECT COUNT(*) FROM route_health").fetchone()[0] != 0:
            raise ValueError("Remote MegaPlay catalog must not contain device health")


def sha256_file(path: Path | str) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class AnikotoClient:
    def __init__(
        self,
        *,
        base_url: str = DEFAULT_BASE_URL,
        request_interval_seconds: float = DEFAULT_REQUEST_INTERVAL_SECONDS,
        timeout_seconds: float = 25.0,
        max_retries: int = 4,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.request_interval_seconds = max(0.0, request_interval_seconds)
        self.timeout_seconds = timeout_seconds
        self.max_retries = max_retries
        self._last_request_started: float | None = None

    def get_json(self, path: str, query: Mapping[str, Any] | None = None) -> Mapping[str, Any]:
        encoded_path = "/".join(urllib.parse.quote(part, safe="") for part in path.split("/") if part)
        url = f"{self.base_url}/{encoded_path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)

        for attempt in range(self.max_retries + 1):
            self._throttle()
            request = urllib.request.Request(
                url,
                headers={"Accept": "application/json", "User-Agent": USER_AGENT},
            )
            self._last_request_started = time.monotonic()
            try:
                with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                    status = getattr(response, "status", 200)
                    if status == 403:
                        raise AnikotoFatalError("Anikoto returned 403; aborting without publish")
                    body = response.read()
                    decoded = json.loads(body.decode("utf-8"))
                    if not isinstance(decoded, Mapping):
                        raise ValueError("Anikoto response is not a JSON object")
                    return decoded
            except urllib.error.HTTPError as error:
                if error.code == 403:
                    raise AnikotoFatalError("Anikoto returned 403; aborting without publish") from error
                if error.code == 429 and attempt < self.max_retries:
                    retry_after = _parse_retry_after(error.headers.get("Retry-After"))
                    time.sleep(max(retry_after, 120.0))
                    continue
                if 500 <= error.code < 600 and attempt < self.max_retries:
                    time.sleep(min(30.0, 2.0 ** attempt))
                    continue
                raise
            except (urllib.error.URLError, TimeoutError):
                if attempt >= self.max_retries:
                    raise
                time.sleep(min(30.0, 2.0 ** attempt))
        raise AssertionError("unreachable")

    def _throttle(self) -> None:
        if self._last_request_started is None:
            return
        remaining = self.request_interval_seconds - (
            time.monotonic() - self._last_request_started
        )
        if remaining > 0:
            time.sleep(remaining)


def _parse_retry_after(value: str | None) -> float:
    if value is None:
        return 0.0
    try:
        return max(0.0, float(value))
    except ValueError:
        return 0.0


def _extract_recent_rows(payload: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    containers: list[Any] = [
        payload.get("data"),
        payload.get("anime"),
        payload.get("animes"),
        payload.get("results"),
        payload.get("items"),
    ]
    data = _mapping(payload.get("data"))
    containers.extend(
        [
            data.get("anime"),
            data.get("animes"),
            data.get("results"),
            data.get("items"),
        ]
    )
    for candidate in containers:
        if isinstance(candidate, list):
            return [item for item in candidate if isinstance(item, Mapping)]
    return []


def _has_next_page(payload: Mapping[str, Any], page: int, row_count: int, per_page: int) -> bool:
    pagination = _mapping(payload.get("pagination"))
    if not pagination:
        pagination = _mapping(_mapping(payload.get("data")).get("pagination"))

    for key in ("has_next_page", "hasNextPage", "has_next", "hasNext"):
        value = pagination.get(key)
        if isinstance(value, bool):
            return value

    current = _positive_int(
        _first_value([pagination], ("current_page", "currentPage", "page"))
    ) or page
    last = _positive_int(
        _first_value(
            [pagination],
            ("last_page", "lastPage", "total_pages", "totalPages", "pages"),
        )
    )
    if last is not None:
        return current < last
    return row_count >= per_page and row_count > 0


def _series_id_from_recent(row: Mapping[str, Any]) -> str | None:
    return _clean_id(
        _first_value(
            [row],
            ("id", "series_id", "seriesId", "anime_id", "animeId", "slug"),
        )
    )


def collect_snapshots(
    client: AnikotoClient,
    *,
    mode: str,
    per_page: int = DEFAULT_PER_PAGE,
    incremental_pages: int = DEFAULT_INCREMENTAL_PAGES,
    max_full_pages: int = 10_000,
) -> tuple[list[SeriesSnapshot], CollectionStats]:
    if mode not in {"incremental", "full"}:
        raise ValueError("mode must be incremental or full")
    if per_page <= 0 or per_page > 500:
        raise ValueError("per_page must be between 1 and 500")

    stats = CollectionStats()
    snapshots: dict[str, SeriesSnapshot] = {}
    page_limit = incremental_pages if mode == "incremental" else max_full_pages

    for page in range(1, page_limit + 1):
        listing = client.get_json(
            "recent-anime",
            {"page": page, "per_page": per_page},
        )
        rows = _extract_recent_rows(listing)
        stats.pages += 1
        stats.rows_seen += len(rows)
        if not rows:
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
            except Exception as error:  # keep one malformed/temporary series from killing the snapshot
                print(
                    f"warning: failed series {series_id}: {type(error).__name__}: {error}",
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

        if mode == "incremental" and page >= incremental_pages:
            break
        if not _has_next_page(listing, page, len(rows), per_page):
            break

    return list(snapshots.values()), stats


def _write_stats(path: Path | None, stats: CollectionStats, *, mode: str) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {"schemaVersion": 1, "mode": mode, **stats.to_json()},
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the isolated GoAnime MegaPlay cache")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--previous-database", type=Path)
    parser.add_argument("--mode", choices=("incremental", "full"), default="incremental")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--per-page", type=int, default=DEFAULT_PER_PAGE)
    parser.add_argument("--incremental-pages", type=int, default=DEFAULT_INCREMENTAL_PAGES)
    parser.add_argument("--request-interval", type=float, default=DEFAULT_REQUEST_INTERVAL_SECONDS)
    parser.add_argument("--stats-json", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.validate_only:
        validate_catalog_database(args.output)
        return 0

    client = AnikotoClient(
        base_url=args.base_url,
        request_interval_seconds=args.request_interval,
    )
    snapshots, stats = collect_snapshots(
        client,
        mode=args.mode,
        per_page=args.per_page,
        incremental_pages=args.incremental_pages,
    )
    if not snapshots and not (
        args.previous_database is not None and args.previous_database.exists()
    ):
        raise RuntimeError("collector produced no mapped series and no previous snapshot exists")

    build_catalog_database(
        args.output,
        snapshots,
        previous_database=args.previous_database,
    )
    _write_stats(args.stats_json, stats, mode=args.mode)
    print(
        json.dumps(
            {
                "output": str(args.output),
                "sha256": sha256_file(args.output),
                "sizeBytes": args.output.stat().st_size,
                **stats.to_json(),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
