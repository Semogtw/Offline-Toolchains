# Public runner CI hub

`Offline-Toolchains` is the canonical public-runner home for expensive verification and build work that can safely be moved out of the actively developed repositories. Private repositories are checked out with a fine-grained read-only token; project outputs are discarded unless a dedicated encrypted-transfer workflow explicitly packages them.

The security invariants are defined in `docs/WORKFLOW_HUB_SECURITY.md` and machine-checked by `scripts/validate-workflow-hub-security.py`.

## Supported projects

| Project input | Repository | Default ref | Central gate |
| --- | --- | --- | --- |
| `goanime` | `Semogtw/goanime-mobile` | `main` | Flutter health, format, analysis, tests, release-workflow validation, debug APK build-and-discard |
| `zapzap` | `Semogtw/Zapzap` | `development/android-build-recovery` | source/pure checks, Android baseline, unit tests, lint, debug APK build-and-discard |
| `semogsite` | `Semogtw/SemogSite` | `main` | frozen pnpm install, confidentiality/boundary gates, focused orchestration tests, full monorepo check, build and isolated Playwright gate |
| `hydra` | `Semogtw/HydraPersonalizado` | `main` | pinned Node/Yarn, GTK4 Layer Shell, Rust, typechecks, tests, format/ESLint and build |
| `receitas` | `Semogtw/Receitas` | `main` | dedicated Node/pnpm source audits, lint, typecheck, unit tests and static Pages build via `Run Receitas CI` |
| `fichario` | `Semogtw/FicharioVirtual` | `main` | token-free public checkout and `pnpm verify:full` in the dedicated Fichário workflow |

Repository identity and commands are fixed in trusted code. Request payloads select only an allowlisted key/ref contract; they cannot supply a repository, runner, command, script, secret, or output destination.

## Private repository token

`PRIVATE_REPOSITORIES_TOKEN` must be a fine-grained PAT with only `Contents: Read-only` for:

- `goanime-mobile`
- `Zapzap`
- `SemogSite`
- `HydraPersonalizado`
- `Receitas`

Do not grant write access, Actions administration, secrets, packages, or unrelated repositories. Rotate the token and keep an expiration date.

Every private checkout uses shallow fetches, `persist-credentials: false`, no LFS/submodules, and `show-progress: false`. Each private job removes its checkout in an `always()` cleanup step. Persistent Actions dependency caches are intentionally disabled for private checkouts.

## Running the hub

For the shared private profiles use `Actions → Run private project CI`; select a project and optional exact branch/tag/SHA. An empty ref uses the table default. Fichário remains a separate token-free `Run Fichario CI` workflow.

Receitas now has a dedicated connector-friendly path because its executable release gates differ from the former planning guard:

1. update only `triggers/receitas-ci.json` on branch `build/receitas-ci`;
2. `Request Receitas CI` validates an owner-authored push and a single safe `ref` field without receiving secrets;
3. trusted `Run Receitas CI` on `main` receives the read-only private checkout token and executes only fixed commands.

A `repository_dispatch` event of type `private-project-ci` is also supported for the legacy/shared private profiles, but direct dispatches are accepted only when GitHub reports the actor as the repository owner.

The connector-friendly shared branch remains `build/private-ci`: update only `triggers/private-ci.json`. `Request private project CI` validates the owner-authored request without secrets, then the trusted workflows normalize the same allowlist and execute only the matching project job.

## Public visibility and confidentiality

The runner repository is public, therefore workflow names, step names, timing, exit status and command output are public. Private source is not uploaded, and summaries/receipts deliberately omit private repository/ref details and resolved private commit hashes where practical.

Do not add shell xtrace (`set -x`) to private-token workflows, dump environments, print source files, or upload raw diagnostic logs. Tests that naturally print filenames/test names should be reviewed before being added to the public hub.

## Artifacts, APKs and retention

Normal CI jobs do not use `actions/upload-artifact`; APKs, installers, reports, production bundles and build directories are verified and discarded with the runner.

When a private artifact must be downloadable, it must use a dedicated transfer workflow following the GoAnime pattern: build from a fixed private repository/ref, validate locally, encrypt with the committed OpenPGP public key, remove plaintext/private checkout, and upload only ciphertext plus sanitized metadata. The private decryption key never enters Actions.

All uploaded artifacts in this repository have a maximum configured retention of **1 day**. This short retention is defense in depth; sensitive artifacts must still be encrypted before upload.

## SemogSite

SemogSite now follows integrated `main`, not the old bootstrap branch. The public hub mirrors the stronger workflow-control gate: exact pnpm install, native SQLite verification, package/confidentiality checks, focused orchestration/database/web tests, full monorepo check, production build and isolated Playwright privacy/mobile navigation test. No project-derived Actions cache is retained.

## Hydra

Hydra remains compatible with its dedicated validation/toolchain workflows, but the general private-project hub can now execute the same repository-level class of gates. It installs Node 22.23.1, Yarn 1.22.22, pinned GTK4 Layer Shell prerequisites and Rust before running typechecks, tests, formatting/ESLint and a build. Source and outputs are removed afterward.

## Receitas

Receitas is now an executable React/TypeScript PWA. `Run Receitas CI` uses Node 24.18.0 and the `packageManager` pinned by the private repository, then attempts these fixed, non-E2E gates:

- release-script tests;
- source/security/PWA/UI integration audits;
- ESLint;
- TypeScript;
- unit tests;
- static Cloudflare Pages build plus browser-artifact audits.

The public runner uses only synthetic public `VITE_*` values ending in `.invalid`; it receives no E2E password, service-role key, Supabase project credential, PowerSync credential or deploy credential.

A missing `pnpm-lock.yaml` is a release blocker. While that gap exists, the workflow deliberately performs an **ephemeral non-frozen dependency resolution** so independent compile/test failures can still be discovered, then marks the job failed for the missing reproducibility contract. Once the lockfile exists, install automatically switches to `pnpm install --frozen-lockfile`.

E2E that requires the dedicated Receitas staging identity, real Supabase/PowerSync state or destructive restore opt-ins remains outside this public runner. Production deploy and privileged backend provisioning also remain outside it.

The older `receitas` job inside `Run private project CI` remains only as a compatibility/planning guard while callers migrate to the dedicated trigger; the inventory's canonical `central_ci` is `run-receitas-ci`.

## Sanitized run receipts

`Report private project CI runs` writes completed shared-hub results to the open **Public private CI run receipts** issue #15. Receipts include public run metadata and the selected project job/result only. Private source, private commit/ref details, logs, artifacts, secrets and build outputs are intentionally omitted.

The dedicated Receitas runner currently reports only through its sanitized GitHub Step Summary and does not upload an artifact or write private ref/SHA details to the public receipt issue.

## Validation

Run after changing the hub:

```bash
python3 scripts/test_private_ci_request.py
python3 scripts/test-private-ci-toolchain-policy.py
python3 scripts/test-semogsite-install-policy.py
python3 scripts/validate-private-ci-workflows.py
python3 scripts/validate-workflow-hub-security.py
```

The repository workflows run these gates on relevant changes.

## Deliberate boundary

Signing keys, Firebase/production credentials, TURN credentials, deployment credentials, production databases and release publication are not moved into a broad public CI job merely to save minutes. A public runner may build a private artifact for encrypted handoff, but privileged signing/deployment needs a separately reviewed threat model and least-privilege credential path.
