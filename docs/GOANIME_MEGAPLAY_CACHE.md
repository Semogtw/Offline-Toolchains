# GoAnime MegaPlay English cache

This cache belongs to the opt-in MegaPlay English Mode in `Semogtw/goanime-mobile`.
It is intentionally independent from the normal PT-BR provider cache and is not
consumed when the mode is disabled.

## Publication

Workflow: `.github/workflows/goanime-megaplay-cache.yml`

Stable GitHub release tag: `goanime-megaplay-cache-latest`

The GitHub Release is the canonical, self-contained public mirror. Its
`manifest.json` always points to the content-addressed database asset in that
same release:

```text
https://github.com/Semogtw/Offline-Toolchains/releases/download/
  goanime-megaplay-cache-latest/manifest.json
https://github.com/Semogtw/Offline-Toolchains/releases/download/
  goanime-megaplay-cache-latest/megaplay_catalog_<sha-prefix>.db
```

The SQLite object is uploaded before the manifest. `manifest.json` is the
visible generation switch and is published after the active database asset has
been validated and uploaded.

Cloudflare R2 is optional acceleration, not a dependency of the GitHub mirror.
When an R2 public base is configured, the workflow builds a separate
`manifest-r2.json` whose asset URL points to R2. The R2 namespace is:

```text
/latest/megaplay/manifest.json
/latest/megaplay/megaplay_catalog_<sha-prefix>.db
/latest/megaplay/collection_stats.json
```

The optional R2 public base is resolved in this order:

1. `MEGAPLAY_CACHE_PUBLIC_BASE_URL` secret;
2. sibling `/megaplay` path derived from the existing `UPDATE_MANIFEST_URL`;
3. no R2 publication when neither is configured.

R2 publication reuses the existing GoAnime secrets:

- `CLOUDFLARE_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`

Incomplete or absent R2 credentials only skip the optional R2 upload. They do
not invalidate a successfully published GitHub Release generation.

## Refresh policy

- recent pages: every 6 hours;
- historical backfill: daily;
- Anikoto requests are spaced by at least 2.05 seconds;
- `429` honors retry/backoff and never causes an immediate retry storm;
- `403` aborts the run so the previous known-good snapshot remains published;
- the historical cursor is stored inside `cache_meta.backfillNextPage`;
- reaching the end wraps the cursor back to the first historical page after the
  recent window.

The collector updates a copy of the previous snapshot. A temporary failure for
one title therefore leaves its previous entry intact instead of deleting it.
Publication is refused when more than 20% of requested series fail in one run.

## Mapping policy

Only strong identities become authoritative remote availability:

- MAL ID;
- AniList ID.

Title-only matches are intentionally rejected. The app still has deterministic
MegaPlay MAL/AniList playback routes even when a title is absent from this seed.
The seed exists to accelerate availability/episode discovery and provide
`episode_embed_id` hints, not to become the sole playback source of truth.

## Stored data

The remote SQLite schema mirrors the mode-local cache tables so it can be
validated and imported without translation ambiguity:

- `series_identity`;
- `episode_availability`;
- `route_health` (must be empty in a remote snapshot);
- `cache_meta`.

It stores only public durable routing hints: canonical IDs, Anikoto series ID,
episode number, `episode_embed_id`, SUB/DUB availability, timestamps and mapping
confidence.

It never stores cookies, authorization, user identifiers, history, request
headers, signed media URLs or complete MegaPlay embed URLs.

## Validation

Local/CI unit tests:

```bash
python -m unittest discover -s tests -p 'test_megaplay_cache_builder.py' -v
python -m compileall -q tools/megaplay_cache tests/test_megaplay_cache_builder.py
```

Validate a generated database:

```bash
python -m tools.megaplay_cache.build_megaplay_cache \
  --output path/to/megaplay_catalog.db \
  --validate-only
```

Validation requires SQLite `PRAGMA integrity_check = ok`, schema version 1,
required columns, canonical MAL/AniList keys, valid episode availability values,
and no device-local route health in the remote database.
