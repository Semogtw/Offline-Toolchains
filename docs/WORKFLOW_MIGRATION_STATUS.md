# Workflow migration status

This document records which development workflows are intentionally owned by the public `Offline-Toolchains` hub and which operations must remain source-local because of repository events, environments, deployment credentials, or protected service state.

The default rule is: **heavy build/test/toolchain compute from private projects belongs here; credentials with write/deploy/signing authority do not move into a generic public workflow simply to save Actions minutes.** For projects that are already public, hosted-runner compute is already free, so centralization is used only when it reduces duplication or provides shared tooling; repository-event and protected-environment workflows stay local when moving them would add credentials or cross-repository dispatch complexity without a billing benefit.

## Centralized now

### GoAnime

- Full Flutter/tooling/core CI: `Run private GoAnime full CI`.
- General private-project Android verification: `Run private project CI`.
- Encrypted debug APK handoff.
- Encrypted source export.
- Windows/Linux desktop smoke on public runners.
- Incremental catalog refresh with encrypted APK output.

The old heavy private `ci.yml` and `desktop_smoke.yml` implementations were replaced by **manual-only compatibility markers** because GoAnime architecture/health tests intentionally read those file paths. They no longer have push, pull-request or schedule triggers and do not receive private credentials. The former `android_debug_build.yml` was removed completely. Heavy compute therefore runs only in the public hub.

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
- Public Hydra dependency-toolchain artifacts now contain only public third-party caches plus SHA-256 compatibility fingerprints; raw private `package.json`, Yarn/Cargo lockfiles and the selected private ref are removed before upload.

Hydra currently has no `.github/workflows` directory in the private repository.

### Receitas

- Planning/documentation guard.
- Encrypted source export.

The guard deliberately fails once an executable stack appears unless a real runtime profile has first been added to the hub.

### Fichário Virtual

`Semogtw/FicharioVirtual` is already public, so its hosted Actions are already free. `Run Fichario CI` in this hub executes `pnpm verify:full`, which covers the ordinary heavy verification surface: lint, Svelte checks, unit tests, production build, Playwright E2E, offline source gates, Edge Function checks and local database gates.

The following source-local workflows are intentionally **not duplicated** in Toolchains:

- documentation-only formatting checks: already subsumed by the full hub verification and cheap in the public source repository;
- deployment-artifact construction: depends on environment-specific public Supabase configuration and is already free in the public repository;
- Supabase staging deployment: uses the protected `staging-deploy` environment plus Supabase access/database credentials;
- Supabase/OCR staging verification: uses protected `staging` credentials and, for OCR, explicit external-provider consent;
- deployed-site verification: event/input-local utility with no private-runner billing benefit.

This preserves environment approvals and secrets at the repository that owns the deployment while keeping shared build/test orchestration in Toolchains.

### Public Codex/Gemini repositories

`Semogtw/codex-desktop-linux-gemini-` and `Semogtw/codex-gemini-agents` are public and therefore already receive free hosted-runner compute. They contain repository-event workflows such as CI/Bazel, Cachix/Nix, dependency setup, upstream build/update tasks, contributor/PR policies, labels, issue automation and post-merge checks.

Those event-local workflows remain in their public source repositories because moving them to another repository would require cross-repository dispatch/permissions while providing no Actions billing advantage. `Offline-Toolchains` remains the canonical home for reusable/offline toolchain artifacts and cross-project build infrastructure; source-repository governance automation remains beside the events it governs.

If one of these repositories becomes private later, its heavy build/test jobs must be re-evaluated immediately for the same public-runner private-checkout pattern used by GoAnime/ZapZap/SemogSite/Hydra.

## Privileged GoAnime exceptions still private

The remaining GoAnime workflow definitions are not ordinary CI duplication:

- `anime_metadata_cache.yml` performs repository writes and publishes metadata to R2 using Cloudflare credentials;
- `runtime_database_cache.yml` publishes runtime databases to R2 using Cloudflare credentials;
- `build_full_credentialed_apk.yml` handles credentialed APK construction;
- `release.yml` handles release/signing-sensitive work;
- `shorebird_patch.yml` handles Shorebird credentials and patch publication.

Do not copy those credentials wholesale into the public repository.

The catalog refresh already demonstrates the preferred migration model for a privileged write: a general read-only checkout token plus a separate `GOANIME_CATALOG_WRITE_TOKEN` scoped only to the single repository and operation. R2 or release workflows should migrate only after equally narrow credentials are created in `Offline-Toolchains` and the public workflow is constrained to trusted owner-authored triggers.

The two R2 publishers have already been hardened in place: checkout credentials are not persisted, package-manager Actions caches are disabled where private metadata could persist, R2 secrets are scoped to validation/upload steps instead of the whole job, generated publication data is cleaned in `always()`, and redundant raw Actions artifacts are avoided where an external publication already exists.

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

Automatic private-PR-to-public-hub forwarding would require a cross-repository dispatch credential. If added later, use a separate token scoped only to dispatching the trusted public workflow; do not reuse the private-source read token or any release/R2 credential.

For public repositories, keep thin repository-event/governance workflows source-local unless the implementation can be safely factored into a reusable public workflow without changing the security or billing model.

## Verification

Before declaring another private workflow migrated, verify all of the following:

- equivalent functional gates exist in `Offline-Toolchains`;
- the public workflow is accepted by `Validate workflow hub security`;
- private checkout credentials are not persisted;
- private-source caches are not persisted;
- private APK/data uploads are ciphertext-only with one-day retention;
- public toolchain artifacts do not contain raw dependency manifests/lockfiles copied from a private checkout unless the entire artifact is encrypted;
- any write/deploy secret is operation-specific and repository/service-scoped;
- the old private automatic trigger is removed or reduced to a non-automatic migration marker so compute is not duplicated;
- public source-local exceptions have a documented event/environment reason rather than being forgotten duplication.
