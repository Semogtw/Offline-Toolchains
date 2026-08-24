#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Sequence

from .build_megaplay_cache import (
    AnikotoClient,
    build_catalog_database,
    utc_now,
    validate_catalog_database,
)
from .pipeline import (
    collect_page_window,
    read_cache_meta,
    write_cache_meta,
    write_manifest,
)

DEFAULT_RECENT_PAGES = 5
DEFAULT_BACKFILL_PAGES = 5
DEFAULT_PER_PAGE = 100
DEFAULT_REQUEST_INTERVAL = 2.1


def _positive_int(value: str | None, default: int) -> int:
    try:
        parsed = int((value or '').strip())
    except ValueError:
        return default
    return parsed if parsed > 0 else default


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Refresh and publish-ready GoAnime MegaPlay cache artifacts',
    )
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--previous-database', type=Path)
    parser.add_argument('--mode', choices=('recent', 'backfill'), required=True)
    parser.add_argument('--public-base-url', required=True)
    parser.add_argument('--base-url', default='https://anikotoapi.site')
    parser.add_argument('--per-page', type=int, default=DEFAULT_PER_PAGE)
    parser.add_argument('--recent-pages', type=int, default=DEFAULT_RECENT_PAGES)
    parser.add_argument('--backfill-pages', type=int, default=DEFAULT_BACKFILL_PAGES)
    parser.add_argument('--request-interval', type=float, default=DEFAULT_REQUEST_INTERVAL)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    output_dir: Path = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    previous = args.previous_database
    if previous is not None and not previous.exists():
        previous = None
    if previous is not None:
        validate_catalog_database(previous)

    recent_pages = max(1, args.recent_pages)
    if args.mode == 'recent':
        start_page = 1
        page_count = recent_pages
    else:
        stored_cursor = read_cache_meta(previous, 'backfillNextPage') if previous else None
        default_start = recent_pages + 1
        start_page = _positive_int(stored_cursor, default_start)
        if start_page <= recent_pages:
            start_page = default_start
        page_count = max(1, args.backfill_pages)

    client = AnikotoClient(
        base_url=args.base_url,
        request_interval_seconds=max(2.05, args.request_interval),
    )
    snapshots, stats = collect_page_window(
        client,
        start_page=start_page,
        page_count=page_count,
        per_page=args.per_page,
    )

    if not snapshots and previous is None:
        raise RuntimeError('collector produced no strong-ID mappings and no previous snapshot exists')

    working_database = output_dir / 'megaplay_catalog.db'
    build_catalog_database(
        working_database,
        snapshots,
        previous_database=previous,
    )

    if args.mode == 'backfill':
        next_cursor = stats.next_page
        if next_cursor <= recent_pages:
            next_cursor = recent_pages + 1
        write_cache_meta(working_database, 'backfillNextPage', str(next_cursor))
        write_cache_meta(
            working_database,
            'lastBackfillRefreshAt',
            utc_now().isoformat().replace('+00:00', 'Z'),
        )
    else:
        write_cache_meta(
            working_database,
            'lastRecentRefreshAt',
            utc_now().isoformat().replace('+00:00', 'Z'),
        )

    validate_catalog_database(working_database)
    manifest_path = output_dir / 'manifest.json'
    manifest = write_manifest(
        working_database,
        manifest_path,
        public_base_url=args.public_base_url,
    )
    asset_name = manifest['asset']['url'].rsplit('/', 1)[-1]
    asset_path = output_dir / asset_name
    shutil.copy2(working_database, asset_path)
    validate_catalog_database(asset_path)

    stats_path = output_dir / 'collection_stats.json'
    stats_path.write_text(
        json.dumps(
            {
                'schemaVersion': 1,
                'mode': args.mode,
                **stats.to_json(),
                'assetName': asset_name,
                'assetSha256': manifest['asset']['sha256'],
                'assetSizeBytes': manifest['asset']['sizeBytes'],
                'catalog': manifest['catalog'],
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ) + '\n',
        encoding='utf-8',
    )

    print(
        json.dumps(
            {
                'manifest': str(manifest_path),
                'asset': str(asset_path),
                'stats': str(stats_path),
                'mode': args.mode,
                **stats.to_json(),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
