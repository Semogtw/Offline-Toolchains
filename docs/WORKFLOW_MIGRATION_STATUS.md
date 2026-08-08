# Workflow migration status

This document records which development workflows are intentionally owned by the public `Offline-Toolchains` hub and which privileged operations still belong to a private consumer repository.

The default rule is: **heavy build/test/toolchain compute belongs here; credentials with write/deploy/signing authority do not move into a generic public workflow simply to save Actions minutes.**

## Centralized now

### GoAnime

- Full Flutter/tooling/core CI: `Run private GoAnime full CI`.
- General private-project Android verification: `Run private project CI`.
- Encrypted debug APK handoff.
- Encrypted source export.
- Windows/Linux desktop smoke on public runners.
- Incremental catalog refresh with encrypted APK output.

The former private `ci.yml`, `desktop_smoke.yml` and `android_debug_build.yml` have been retired or removed so they no longer consume private hosted-runner minutes or produce billing-failure checks.

### ZapZap

- Android source/pure checks, unit tests, lint and debug build-and-discard.
- Encrypted debug APK handoff.
- Encrypted source export.

No `.github/workflows` directory exists on the active ZapZap branch, so heavy Actions work is not duplicated there.

### SemogSite

- Full monorepo workflow-control gate is implemented in `Run private project CI`.
- Encrypted source export is implemented in the shared source-bundle workflow.

The former heavy private workflow has been reduced to a manual migration marker only; it no longer runs on push or pull request.

### Hydra

- Native prerequisites, Node/Yarn, Rust, typechecks, tests, formatting/ESLint and build-and-discard.
- Encrypted source export.
- Dedicated validation/toolchain profiles remain in this public repository.

Hydra currently has no `.github/workflows` directory in the private repository.

### Receitas

- Planning/documentation guard.
- Encrypted source export.

The guard deliberately fails once an executable stack appears unless a real runtime profile has first been added to the hub.

### Fichário Virtual

The source repository is public, so moving a workflow is not required for free hosted-runner eligibility. The hub still provides `Run Fichario CI` for shared orchestration and connector-friendly verification.

## Privileged GoAnime exceptions still private

The remaining GoAnime workflow definitions are not ordinary CI duplication:

- `anime_metadata_cache.yml` performs repository writes and publishes metadata to R2 using Cloudflare credentials.
- `runtime_database_cache.yml` publishes runtime databases to R2 using Cloudflare credentials.
- `build_full_credentialed_apk.yml` handles credentialed APK construction.
- `release.yml` handles release/signing-sensitive work.
- `shorebird_patch.yml` handles Shorebird credentials and patch publication.

Do not copy those credentials wholesale into the public repository.

The catalog refresh already demonstrates the preferred migration model for a privileged write: a general read-only checkout token plus a separate `GOANIME_CATALOG_WRITE_TOKEN` scoped only to the single repository and operation. R2 or release workflows should migrate only after equally narrow credentials are created in `Offline-Toolchains` and the public workflow is constrained to trusted owner-authored triggers.

## Pending secret relocation

Two GoAnime operations are technically suitable for further public-runner migration once dedicated secrets are provisioned:

1. metadata/R2 publication;
2. runtime database/R2 publication.

A safe migration should:

- keep `PRIVATE_REPOSITORIES_TOKEN` read-only;
- use a dedicated R2 access key/token restricted to the exact bucket and operations needed;
- inject R2 credentials only into the upload step rather than job-wide environment;
- never upload an additional raw Actions artifact when the output is already published intentionally to R2;
- avoid printing bucket/account/credential values;
- clean the private checkout and generated local data in `always()`;
- retain any unavoidable sensitive transfer for one day and encrypt it first.

Until those secret names/values are provisioned in the public hub, the existing private definitions remain the credential boundary even though private hosted jobs may currently be blocked by account billing/spending state.

## Trigger model

Public hub workflows use fixed repository mappings and allowlisted refs. The current GoAnime full CI also runs daily so `main` retains automated coverage after removing the private push CI.

Automatic PR-to-public-hub forwarding would require a cross-repository dispatch credential. If added later, use a separate token scoped only to dispatching the trusted public workflow; do not reuse the private-source read token or any release/R2 credential.

## Verification

Before declaring another private workflow migrated, verify all of the following:

- equivalent functional gates exist in `Offline-Toolchains`;
- the public workflow is accepted by `Validate workflow hub security`;
- private checkout credentials are not persisted;
- private-source caches are not persisted;
- private APK/data uploads are ciphertext-only with one-day retention;
- any write/deploy secret is operation-specific and repository/service-scoped;
- the old private automatic trigger is removed or reduced to a non-automatic migration marker so compute is not duplicated.
