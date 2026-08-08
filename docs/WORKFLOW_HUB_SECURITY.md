# Workflow hub security and consolidation policy

`Offline-Toolchains` is the canonical home for expensive CI, build, cache and encrypted-transfer workflows used by the actively developed projects listed in `config/workflow-hub-projects.json`.

The goal is to keep GitHub-hosted compute in this public repository whenever the work can safely run here, while treating private source and generated outputs as confidential by default.

## Core rules

1. **Private source is ephemeral.** Checkouts of private repositories use a fine-grained, read-only token, `persist-credentials: false`, no LFS/submodules unless a profile explicitly requires them, and are removed in an `always()` cleanup path whenever practical.
2. **No persistent Actions cache for private checkouts.** Package-manager caches derived from private repositories can leak dependency names, paths or build metadata and outlive a runner. Private CI jobs therefore hydrate dependencies inside the disposable runner instead of using `actions/cache` or setup-action cache integration.
3. **Private build outputs are discarded by default.** Tests may build an APK, installer or production bundle to prove that the build works, but the output is deleted with the checkout unless a transfer workflow explicitly packages it.
4. **Sensitive transfer is ciphertext-only.** APKs, source bundles, diagnostics, databases, backups, signing material and similar data must never be uploaded in plaintext from this public repository. Transfer workflows encrypt first with the committed OpenPGP public key and upload only ciphertext plus sanitized hashes/metadata.
5. **Retention follows sensitivity.** Sensitive/private transfers use `retention-days: 1`. Explicitly public toolchains and redacted public reports may use up to 7 days so they can be reused instead of rebuilt constantly. Every `upload-artifact` must declare its retention explicitly.
6. **Secrets stay out of untrusted code paths.** Workflows that receive `PRIVATE_REPOSITORIES_TOKEN` must not use `pull_request_target`, `secrets: inherit`, persisted checkout credentials, arbitrary repository/command inputs, or code from request branches as privileged implementation.
7. **Least privilege by workflow.** Workflows declare explicit permissions. Private checkout/build jobs use `contents: read`; reporter workflows may add only the narrow write capability they require.
8. **Public logs are treated as public.** Private jobs must avoid debug logging and should not print secret values, environment dumps, private source contents, user data, or sensitive manifests.

## Active project coverage

The versioned inventory is `config/workflow-hub-projects.json`.

Current central coverage:

- GoAnime: private CI, Android debug verification, encrypted APK transfer, encrypted source export and incremental catalog refresh.
- ZapZap: private Android CI, encrypted debug APK transfer and encrypted source export.
- SemogSite: private checks/builds, public offline toolchain and encrypted source export. The CI default follows integrated `main`, not an old bootstrap branch.
- Hydra: private validation, public offline toolchain and encrypted source export.
- Receitas: repository is currently planning/documentation-first. It is registered now so source/export and CI policy are ready before executable code lands; its runtime gate must be promoted when the stack is committed.
- Fichário Virtual: public source, so its full verification remains token-free in this repository.
- Codex desktop/Gemini helper repositories: public toolchain workflows remain here and do not need the private token.

Historical or one-shot workflows may remain temporarily for compatibility, but new work should target the canonical shared profiles instead of adding another consumer-specific privileged workflow.

## Secret scope

`PRIVATE_REPOSITORIES_TOKEN` must be a fine-grained token with only `Contents: Read-only` for private repositories actually served by the hub. As private projects are added, expand only the repository allowlist; do not add Actions administration, secrets, packages or write access.

The GoAnime catalog refresh is the only current central workflow that needs to publish generated source data back to a private repository. It uses a separate secret named `GOANIME_CATALOG_WRITE_TOKEN`, which should be a fine-grained token scoped **only** to `Semogtw/goanime-mobile` with `Contents: Read and write`. The token is injected only into the publish step, used through a one-shot HTTP authorization header, and never persisted by `actions/checkout`.

Any future private consumer that needs cross-repository writes must get its own narrowly scoped credential. Do not reuse the read-only checkout token for writes and do not create one organization-wide write token for convenience.

## APK and binary outputs

A private build job may create an APK/installer only inside the disposable checkout to verify the build. It must not feed that plaintext path to `actions/upload-artifact`.

For downloadable private binaries, follow the shared encrypted-transfer pattern now used by GoAnime and ZapZap:

- resolve and validate the source ref using a fixed repository mapping;
- build in the private checkout;
- validate the binary before packaging;
- calculate a plaintext SHA-256 and size for sanitized transfer metadata;
- import only the public OpenPGP key and verify its pinned fingerprint;
- encrypt into a separate transfer directory;
- remove the private checkout, plaintext binary/archive and temporary keyring **before** upload;
- upload only `.gpg` ciphertext and sanitized metadata;
- set `retention-days: 1`;
- perform an `always()` cleanup as a fallback if an earlier step fails.

The private decryption key must never enter GitHub Actions. Production signing/deployment credentials are not introduced into the public runner merely to create a downloadable build; ZapZap's centralized handoff intentionally produces its ordinary debug-signed APK and then encrypts it.

## Validation

`Validate workflow hub security` runs the static policy checker. It enforces explicit bounded artifact retention, one-day retention for sensitive/private transfers, ciphertext-only private APK/data uploads, non-persisted private checkout credentials and selected cache/permission invariants.

When a legitimate workflow needs an exception, document the exact threat model and scope it narrowly instead of weakening the global rule.
