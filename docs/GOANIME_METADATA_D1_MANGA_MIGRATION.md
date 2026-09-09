# GoAnime metadata D1 Manga migration

This runbook owns the production-safe handoff for adding the Manga search schema to the GoAnime metadata D1 database while keeping all GitHub Actions execution inside `Semogtw/Offline-Toolchains`.

## Fixed source

The currently validated GoAnime source is:

- repository: `Semogtw/goanime-mobile`
- branch: `feat/manga-a71-indexing-supervisor`
- source SHA: `e84e231ac7b5b8777a70732045e07cff8591713d`
- required base SHA: `f71a6d91ceccfa09addb84ed264a3bbee4c7f796`
- migration path: `cloudflare/metadata-worker/migrations/0002_manga_search.sql`
- migration Git blob SHA: `01f1db9c989b810e4fc1e5b32c5149bdd23213ba`

The migration workflow verifies the branch, source SHA, ancestry and migration blob before any Cloudflare mutation.

## Workflows

Read-only readiness:

- `.github/workflows/probe-goanime-metadata-cloudflare-readiness.yml`
- trigger directory: `triggers/goanime-metadata-cloudflare-readiness/`
- may inspect the D1 schema and Worker bindings, but never migrates, imports or deploys.

D1 migration:

- `.github/workflows/goanime-metadata-d1-migrate.yml`
- trigger directory: `triggers/goanime-metadata-d1-migrate/`
- never creates a database and never deploys or edits a Worker.
- applies only `0002_manga_search.sql` and only when the remote schema is exactly `legacy-6` and the request explicitly contains `"apply": true`.
- treats an exact `manga-8` schema as an idempotent no-op.
- refuses empty, partial or unknown schemas.
- verifies the exact eight-table schema after the operation.

## Cloudflare credential

The Toolchains repository must receive an account-scoped Cloudflare API token as repository secret `CLOUDFLARE_API_TOKEN`. `CF_API_TOKEN` is accepted as a compatibility fallback.

Use least privilege:

- D1 migration requires account D1 write/edit access for the GoAnime Cloudflare account.
- the read-only readiness probe also reads Worker settings, so a token intended to run that full probe needs Workers Scripts read access in addition to D1 read/write access.
- scope the token to the specific Cloudflare account instead of all accounts.

`CLOUDFLARE_ACCOUNT_ID` and `GOANIME_CATALOG_WRITE_TOKEN` are separate required secrets. The latter only reads the private GoAnime source checkout.

## Current credential state

On 2026-09-09, readiness runs `34411587274` and `34412098138` established that:

- `CLOUDFLARE_ACCOUNT_ID` is present in Toolchains.
- `GOANIME_CATALOG_WRITE_TOKEN` is present in Toolchains.
- neither `CLOUDFLARE_API_TOKEN` nor `CF_API_TOKEN` is present in Toolchains.

Therefore the remote D1 schema has not yet been inspected by this new readiness path and no migration request must be committed yet.

## Migration request

After the Cloudflare token is configured and a fresh readiness probe confirms the environment, add exactly one new request file under `triggers/goanime-metadata-d1-migrate/` with this contract:

```json
{
  "sourceBranch": "feat/manga-a71-indexing-supervisor",
  "sourceSha": "e84e231ac7b5b8777a70732045e07cff8591713d",
  "baseSha": "f71a6d91ceccfa09addb84ed264a3bbee4c7f796",
  "migrationBlobSha": "01f1db9c989b810e4fc1e5b32c5149bdd23213ba",
  "apply": true
}
```

Do not pre-create or reuse a migration request. Adding the request is the explicit authorization and trigger for the D1 workflow.

## Expected schema transitions

`legacy-6` contains:

- `snapshot_versions`
- `snapshot_datasets`
- `anime_search_items`
- `anime_search_terms`
- `producer_search_items`
- `producer_search_terms`

`manga-8` adds:

- `manga_search_items`
- `manga_search_terms`

The workflow only allows `legacy-6 -> manga-8` or `manga-8 -> manga-8` (no-op). Every other observed table set fails closed.

## Atomicity

The migration file is sent to the Cloudflare D1 query API as one multi-statement SQL batch. It is not split into independent network calls. The workflow requires all returned statement results to report success and then independently re-reads the schema before reporting completion.

## Verification evidence

- GoAnime immutable source verification: Offline-Toolchains run `34411272696`.
- Cloudflare token fallback TDD GREEN: Toolchain security run `34412048568`.
- D1 migration workflow contract GREEN: Toolchain security run `34412442433`.

No GitHub Action is required or intentionally triggered in `Semogtw/goanime-mobile` for this process.
