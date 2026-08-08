# Public runner CI hub

`Offline-Toolchains` is the canonical public-runner home for expensive verification and build work that can safely be moved out of the actively developed repositories. Private repositories are checked out with a fine-grained read-only token; project outputs are discarded unless a dedicated encrypted-transfer workflow explicitly packages them.

The security invariants are defined in `docs/WORKFLOW_HUB_SECURITY.md` and machine-checked by `scripts/validate-workflow-hub-security.py`.

## Supported projects

| Project input | Repository | Default ref | Central gate |
| --- | --- | --- | --- |
| `goanime` | `Semogtw/goanime-mobile` | `main` | Flutter health, format, analysis, tests, release-workflow validation, debug APK build-and-discard |
| `zapzap` | `Semogtw/Zapzap` | `development/android-build-recovery` | source/pure checks, Android baseline, unit tests, lint, debug APK build-and-discard |
| `semogsite` | `Semogtw/SemogSite` | `main` | frozen pnpm install, confidentiality/boundary gates, focused orchestration tests, full monorepo check, build and isolated Playwright gate |
| `hydra` | `Semogtw/HydraPersonalizado` | `main` | pinned Node/Yarn, native GTK dependency, Rust, typechecks, tests, format/ESLint, build-and-discard |
| `receitas` | `Semogtw/Receitas` | `main` | planning/documentation repository guards; intentionally fails when an executable stack appears until the profile is promoted |
| `fichario` | `Semogtw/FicharioVirtual` | `main` | token-free public checkout and `pnpm verify:full` in the dedicated Fichário workflow |

Repository identity and commands are fixed in trusted code. Request payloads select only an allowlisted key and a validated Git ref; they cannot supply a repository, runner, command, script, secret, or output destination.

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

For private projects use `Actions → Run private project CI`; select a project and optional exact branch/tag/SHA. An empty ref uses the table default. Fichário remains a separate token-free `Run Fichario CI` workflow.

A `repository_dispatch` event of type `private-project-ci` is also supported for the private profiles, but direct dispatches are accepted only when GitHub reports the actor as the repository owner.

The connector-friendly branch remains `build/private-ci`: update only `triggers/private-ci.json`. `Request private project CI` validates the owner-authored request without secrets, then the trusted workflows normalize the same allowlist and execute only the matching project job.

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

Receitas currently contains planning/documentation rather than an executable application. Its guard verifies the expected planning structure, tracked JSON, merge-conflict absence and suspicious secret-like filenames. If a runtime manifest such as `package.json`, `pubspec.yaml`, `Cargo.toml`, Gradle files, `go.mod` or `pyproject.toml` appears, the guard fails with an instruction to promote the CI profile instead of silently reporting incomplete coverage.

## Sanitized run receipts

`Report private project CI runs` writes completed hub results to the open **Public private CI run receipts** issue #15. Receipts include public run metadata and the selected project job/result only. Private source, private commit/ref details, logs, artifacts, secrets and build outputs are intentionally omitted. The reporter has `actions: read` and `issues: write` only.

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
