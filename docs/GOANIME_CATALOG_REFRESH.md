# GoAnime catalog refresh via Offline-Toolchains

This workflow refreshes the catalog bundled by the private `Semogtw/goanime-mobile` application while keeping GitHub Actions work on the public Toolchains repository.

## What it refreshes

`.github/workflows/refresh-private-goanime-catalog.yml` is triggered only by an owner-authored change to `triggers/private-goanime-refresh.json` containing an exact 40-character GoAnime commit SHA.

The workflow:

1. checks out the private source at that exact SHA with the read-only `PRIVATE_REPOSITORIES_TOKEN` and does not persist Git credentials;
2. discovers the current anime season through AniList and refreshes the Jikan metadata/broadcast snapshot;
3. probes the AnimeFire catalog from the hosted runner. When the provider is directly reachable, it runs `dart run tools/cache_builder.dart` in **full mode**. When hosted-runner egress is blocked, it preserves the complete bundled baseline and runs only bounded `--seed-only` probes instead of pretending that an empty scan is a fresh catalog;
4. records the provider outcome as either `full-provider-audit` or `provider-blocked-baseline-plus-runtime-discovery` in the encrypted handoff manifest and workflow summary;
5. maps only newly discovered provider titles through the expensive MAL mapper, then merges those mappings into the previous MAL cache;
6. rebuilds the title/franchise runtime artifacts and rejects title, mode, MAL or franchise count regressions before continuing;
7. runs the normal project health, format, analyze and test gates;
8. builds the debug APK;
9. packages the generated cache assets into a catalog tarball, encrypts both the catalog handoff and APK with the repository OpenPGP public key, and uploads only ciphertext with one-day retention;
10. optionally pushes generated cache files back to private `main` when `GOANIME_CATALOG_WRITE_TOKEN` is configured. Lack of that optional write token must not discard a successful refresh or APK build.

Do not replace a reachable-provider full audit with `--seed-only`: seed-only checks bounded targets and does not enumerate the provider catalog. Conversely, do not disable the baseline guard when a hosted runner is blocked. A zero-result network scan is not evidence that the provider catalog is empty.

## Hosted-runner provider blocking

AnimeFire currently returns HTTP 403 to tested GitHub-hosted Ubuntu, Windows and macOS runners, all using Azure egress. This is an infrastructure/provider reachability limitation, not a reason to shrink the bundled cache.

In that state the workflow deliberately keeps the last complete provider snapshot. Fresh current-season metadata and broadcast data are still rebuilt, and the application can verify recent discovery candidates at runtime on the user's network through its dynamic availability cache. A future run from egress accepted by the provider automatically takes the full-audit branch again.

The GoAnime cache builder itself also treats `sitemap.xml` as acceleration rather than a prerequisite and follows `animes-atualizados/<page>` pagination, so a provider that blocks only its sitemap can still be audited through normal catalog pages.

## Persistence fallback

`GOANIME_CATALOG_WRITE_TOKEN` is intentionally separate from `PRIVATE_REPOSITORIES_TOKEN`. The general private-repository checkout token stays read-only.

When the dedicated write token is absent, the encrypted artifact `goanime-private-full-refresh-encrypted` is the recovery boundary. A trusted client holding the matching private OpenPGP key can download and decrypt `GoAnime-refreshed-catalog.tar.gz.gpg`, verify the SHA-256 recorded in `manifest.json`, and commit the generated cache files to `Semogtw/goanime-mobile` through a separately authenticated GitHub channel.

This design prevents a missing write secret from forcing metadata refreshes, tests and APK builds to be repeated, while avoiding a broad write credential in the public workflow.

## Files persisted by a refresh

- `tools/anime_metadata_seed_targets.json`
- `tools/anime_availability_seed_targets.json`
- `assets/data/anime_metadata_seed.json`
- `assets/data/broadcast_schedule.json`
- `assets/data/available_animes.json`
- `assets/data/available_anime_modes.json`
- `assets/data/mal_availability_map.json`
- `assets/data/mal_availability_unmatched.json`
- `assets/data/title_availability.db`
- `assets/data/franchise_availability_map.json`
- `assets/data/franchise_index.json`
- `assets/data/franchise_availability.db`

## Security invariants

- Public Toolchains never receives the private OpenPGP decryption key.
- Plaintext GoAnime source, generated cache archive and APK exist only inside the ephemeral runner workspace and are deleted by an `always()` cleanup step.
- The uploaded handoff contains ciphertext plus a non-secret integrity manifest only.
- Artifact retention is one day.
- Exact-SHA checkout prevents an unreviewed moving branch from being substituted during a run.
- Cache counts and current-season metadata/broadcast minimums are validated before packaging.
- Provider blocking cannot replace a known-good complete cache with an empty or materially smaller result.
