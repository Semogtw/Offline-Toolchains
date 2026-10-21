#!/usr/bin/env python3
"""Verify the shipped GoAnime Similar Works index without re-running providers.

Legacy: require byte-for-byte equality to the reproducible Octen builder.
MangaBaka authority: verify the pinned, locally audited personal artifact plus
catalog identity, SQL integrity, eligibility and strict top-10 invariants.
"""

from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
from pathlib import Path
import sqlite3

AUTHORITY_POLICY = 'mangabaka_api_score_desc_top10_proprietary_fallback_v1'
AUTHORITY_SHA256 = '88ef0094ccea57f1a21e2a7c2f51a321d6be27d8853bb3c066042b1a37bbab6f'
AUTHORITY_STATS = {
    'edgeCount': 110149,
    'sourceCount': 11064,
    'mangabakaEdgeCount': 17790,
    'fallbackEdgeCount': 92359,
    'mangabakaSourceRoots': 3945,
    'mangabakaConflictedExternalIds': 2,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for buf in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(buf)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def connect_ro(path: Path) -> sqlite3.Connection:
    require(path.is_file() and not path.is_symlink(), f'Invalid input: {path.name}')
    return sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)


def metadata(connection: sqlite3.Connection) -> dict[str, str]:
    return dict(connection.execute('SELECT key, value FROM index_metadata'))


def validate_asset(
    *,
    catalog: Path,
    version: Path,
    asset: Path,
    legacy_rebuilt: Path,
    expected_authority_sha: str = AUTHORITY_SHA256,
    expected_stats: dict[str, int] = AUTHORITY_STATS,
) -> dict[str, int | str]:
    catalog_digest = sha256(catalog)
    require(version.read_text(encoding='utf-8').strip() == catalog_digest,
            'Catalog SHA does not match version descriptor')
    with closing(connect_ro(asset)) as index:
        meta = metadata(index)
        require(meta.get('schemaVersion') == '1', 'Unrecognized SQL schema version')
        require(meta.get('catalogSha256') == catalog_digest,
                'Similar Works SQL does not match bundled catalog SHA')
        policy = meta.get('rankingPolicy')
        if policy is None:  # Existing deterministic Octen index.
            require(sha256(asset) == sha256(legacy_rebuilt),
                    'Legacy shipped SQL differs from reproducible offline build')
            return {'mode': 'legacy_octen', 'catalogSha256': catalog_digest}
        require(policy == AUTHORITY_POLICY, 'Unexpected ranking policy')
        require(sha256(asset) == expected_authority_sha,
                'MangaBaka authority candidate is not the reviewed, hash-pinned artifact')
        require(index.execute('PRAGMA integrity_check').fetchone()[0] == 'ok',
                'Similar Works database integrity failed')
        require(not index.execute('PRAGMA foreign_key_check').fetchall(),
                'Broken Similar Works foreign keys')
        stats = {key: int(meta[key]) for key in expected_stats}
        require(stats == expected_stats, 'Provenance/statistical receipt mismatch')
        require(stats['mangabakaEdgeCount'] + stats['fallbackEdgeCount'] == stats['edgeCount'],
                'MangaBaka/fallback totals inconsistent')
        actual_edges, actual_roots = index.execute('''
            SELECT COUNT(*),COUNT(DISTINCT sourceId) FROM manga_similar_works
        ''').fetchone()
        require(actual_edges == stats['edgeCount'] and actual_roots == stats['sourceCount'],
                'SQL counts differ from metadata')
        broken = index.execute('''
            SELECT COUNT(*) FROM manga_similar_works
            WHERE sourceId=targetId OR rankPosition NOT BETWEEN 1 AND 10
              OR score IS NULL OR typeof(score) NOT IN ('real','integer')
              OR score <= 0 OR score > 1 OR score != score
        ''').fetchone()[0]
        require(broken == 0, 'Self links, invalid positions, or invalid scores')
        gaps = index.execute('''
            SELECT COUNT(*) FROM (
                SELECT sourceId FROM manga_similar_works GROUP BY sourceId
                HAVING MIN(rankPosition)!=1 OR MAX(rankPosition)!=COUNT(*)
                   OR COUNT(*)>10
            )
        ''').fetchone()[0]
        require(gaps == 0, 'Non-contiguous top-10 ranks')
        # Reproduce the catalog's established listability+certification gate;
        # never relax, reclassify or mutate the separate +18 policy.
        with closing(connect_ro(catalog)) as public_catalog:
            allowed = {work_id for (work_id,) in public_catalog.execute('''
                SELECT w.workId FROM works w
                WHERE COALESCE(w.hasAdultContent,1)=0
                  AND EXISTS(SELECT 1 FROM source_links sl
                    WHERE sl.workId=w.workId AND sl.availabilityState!='unavailable')
            ''')}
        used_ids = {work_id for (work_id,) in index.execute('''
            SELECT id.workId FROM manga_similar_ids id WHERE EXISTS(
                SELECT 1 FROM manga_similar_works e
                WHERE e.sourceId=id.id OR e.targetId=id.id)
        ''')}
        require(used_ids <= allowed, 'Similar Works contains unlisted or ineligible catalog IDs')
        require(len(used_ids) > 0, 'Empty Similar Works index')
        return {
            'mode': 'mangabaka_top10',
            'catalogSha256': catalog_digest,
            'indexSha256': expected_authority_sha,
            **stats,
        }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--catalog', type=Path, required=True)
    ap.add_argument('--catalog-version', type=Path, required=True)
    ap.add_argument('--asset', type=Path, required=True)
    ap.add_argument('--legacy-rebuilt', type=Path, required=True)
    args = ap.parse_args()
    print(validate_asset(catalog=args.catalog, version=args.catalog_version,
                         asset=args.asset, legacy_rebuilt=args.legacy_rebuilt))


if __name__ == '__main__':
    main()