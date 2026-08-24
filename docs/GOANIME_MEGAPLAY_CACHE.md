# GoAnime MegaPlay English cache

This cache belongs to the opt-in MegaPlay English Mode in `Semogtw/goanime-mobile`.
It is intentionally independent from the normal PT-BR provider cache and is not
consumed when the mode is disabled.

## Ownership / merged state

The server-side MegaPlay cache infrastructure is already merged to
`Semogtw/Offline-Toolchains` `main`.

- cache pipeline PR `#43` -> merged as
  `dfbf7c3af1bda0363f03544781dcb9d4af0b2896`;
- file-driven refresh trigger PR `#44` -> merged as
  `9c7d7cb6e01e6f0e72eaf9b185926b8bddfc6587`.

The app implementation is still under review in `Semogtw/goanime-mobile#217`.
Its current continuation checklist is documented in:

`docs/handoffs/2026-08-24-megaplay-codex-handoff.md`

inside the GoAnime-Mobile feature branch.

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

## File-driven refresh control plane

The canonical collector supports `workflow_dispatch`, schedule and PR tests.
For automation clients that cannot directly dispatch Actions, a small trusted
file-driven dispatcher is also available.

Dispatcher workflow:

`.github/workflows/dispatch-goanime-megaplay-cache.yml`

Request file:

`triggers/goanime-megaplay-cache.json`

Accepted payload:

```json
{
  "mode": "recent",
  "requested_by": "chatgpt-or-codex",
  "requested_at": "ISO-8601 timestamp"
}
```

`mode` must be exactly one of:

- `recent`;
- `backfill`.

A push changing that file on `main` dispatches the canonical
`goanime-megaplay-cache.yml` workflow. The dispatcher owns no collection or
publication logic; it only validates the request and invokes the canonical
workflow.

The first `recent` request was written in commit
`fb26aaf5a6a9372157d9e4285ccb9558edb99d3a`. The next owner should confirm the
resulting first public release generation and record/fix any operational failure
without weakening validation rules.

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

## Initial/public-generation acceptance checks

Before treating a newly published generation as healthy, verify:

1. `manifest.json` exists in release tag `goanime-megaplay-cache-latest`;
2. one active `megaplay_catalog_<sha-prefix>.db` exists;
3. manifest asset URL points to the active DB in that same GitHub Release;
4. manifest and asset `schemaVersion` are both `1`;
5. SHA-256 in the manifest matches the actual DB;
6. `sizeBytes` matches the actual DB;
7. initial publication has non-zero `seriesCount` and `episodeCount`;
8. remote `route_health` has zero rows;
9. no remote row contains device-only `localVerified` evidence;
10. no cookies, credentials, signed media URLs or user data are present.

If optional R2 publication fails, the canonical GitHub Release may still be
healthy. Do not weaken the GitHub generation checks to accommodate R2.

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

## Related app exact-source gate

The app is validated through:

`.github/workflows/validate-private-goanime-source.yml`

Request file:

`triggers/private-goanime-validate.json`

The current gate runs MegaPlay focused test files in isolated Flutter processes
with a 90-second per-file timeout, which prevents one leaked async resource from
hiding the responsible test file.

At the 2026-08-24 handoff, exact-source run `#31` (`32771058820`) for app SHA
`77ae6ff25f050cb39be31a17b0e2aa3491a261a0` passed analyzer and 15 of 16
focused MegaPlay test files. The only blocker was
`test/widgets/megaplay_episode_list_test.dart`, which timed out after 90 seconds
(exit `124`). The GoAnime-Mobile handoff document contains the required
investigation and merge order.
