# Public runner CI hub

The workflows in this repository execute real project verification on public GitHub-hosted runners. Private repositories use a tightly scoped read-only checkout token. The public Fichário Virtual repository uses a separate token-free workflow.

## Supported projects

| Project input | Repository | Default ref | Commands executed |
| --- | --- | --- | --- |
| `goanime` | `Semogtw/goanime-mobile` | `main` | Flutter health, formatting, analysis, tests, release-workflow validation, debug APK build |
| `zapzap` | `Semogtw/Zapzap` | `development/android-build-recovery` | pure tests, source audit, Android baseline, unit tests, lint, debug APK build |
| `semogsite` | `Semogtw/SemogSite` | `develop/foundation-bootstrap` | pnpm install using frozen mode when a lockfile exists or documented bootstrap mode when absent, guardrails/typechecks/tests, production build |
| `fichario` | `Semogtw/FicharioVirtual` | `main` | frozen pnpm install, Chromium setup, Deno and Supabase CLI setup, then `pnpm verify:full` |

Repository identities and commands are fixed in versioned code. Requests can select only an allowlisted project key and a validated Git ref.

## Private repository secret

The private-project workflow requires this Actions repository secret:

```text
Name: PRIVATE_REPOSITORIES_TOKEN
Type: fine-grained personal access token
Owner: Semogtw
Repository access:
  - goanime-mobile
  - Zapzap
  - SemogSite
Repository permission:
  Contents: Read-only
```

Do not grant write permissions, Actions administration, secrets access, packages access, or access to unrelated repositories. Set an expiration date and rotate the token before it expires.

The token is supplied only to `actions/checkout`. Every private checkout uses:

```yaml
fetch-depth: 1
persist-credentials: false
lfs: false
submodules: false
show-progress: false
```

The checked-out source is removed in an `always()` cleanup step.

The Fichário workflow never receives this token or any repository secret. It checks out the fixed public repository `Semogtw/FicharioVirtual` with credential persistence, LFS, and submodules disabled.

## Manual runs

For private projects, open:

```text
Actions → Run private project CI → Run workflow
```

For Fichário, open:

```text
Actions → Run Fichario CI → Run workflow
```

Select the project where applicable and optionally provide an exact branch, tag, or commit SHA. An empty ref uses the default from the table above.

## API dispatch for private projects

Send a `repository_dispatch` event of type `private-project-ci` to `Semogtw/Offline-Toolchains` using credentials that can dispatch events to this repository:

```json
{
  "event_type": "private-project-ci",
  "client_payload": {
    "project": "goanime",
    "ref": "main"
  }
}
```

Direct dispatches are rejected unless GitHub reports the actor as the repository owner. Payload fields cannot override the repository, runner, command, script, secret, or output destination.

The Fichário workflow intentionally does not expose `repository_dispatch`; use its manual input or the connector request branch.

## Connector request branch

The connector-friendly path does not require `workflow_dispatch` support:

1. update `triggers/private-ci.json` on the permanent `build/private-ci` branch;
2. `Request private project CI` validates that request without project secrets;
3. a successful owner-authored request run triggers the trusted execution workflows;
4. only the job whose normalized project matches the allowlisted key performs a checkout and runs commands.

Example Fichário request:

```json
{
  "project": "fichario",
  "ref": "0123456789abcdef0123456789abcdef01234567"
}
```

Only the trigger JSON should normally change on `build/private-ci`. Do not develop workflow code on that branch.

## Fichário verification

`Run Fichario CI` is isolated from the private-project token and executes the repository's canonical aggregate gate:

```bash
pnpm install --frozen-lockfile
pnpm exec playwright install --with-deps chromium
pnpm verify:full
```

The runner also installs Node.js 22.16, pnpm 10, Deno 2.8.1, and the Supabase CLI. `verify:full` covers frontend lint/typecheck/unit tests/build, Playwright, dependency-free source checks, Edge Function Deno checks, and local Supabase database gates. Docker is provided by the GitHub-hosted Ubuntu runner.

The job summary records the requested ref, resolved public commit, and result. The checkout is deleted in `always()` cleanup and no project artifact is uploaded.

## SemogSite dependency modes

The SemogSite job follows the project's offline-toolchain contract:

- when `pnpm-lock.yaml` exists, CI runs `pnpm install --frozen-lockfile` and rejects manifest drift;
- when the lockfile is absent, CI emits a warning and runs `pnpm install --no-frozen-lockfile` only for the intentional bootstrap state;
- the selected mode is written to the job summary;
- generated files remain inside the ephemeral private checkout and are discarded after checks and build.

Bootstrap mode is not a permanent substitute for reproducibility. After dependency selection stabilizes, generate, review, and commit `pnpm-lock.yaml`; subsequent public CI runs automatically return to frozen mode.

## Public visibility

Workflow runs, step names, exit status, requested ref, resolved commit SHA, and command output are public because the jobs belong to a public repository. Private project source is not uploaded automatically, but build tools and tests may print package names, file paths, test names, diagnostics, or stack traces. Fichário source is already public.

Do not run private refs that contain secrets in tracked files or tests that print credentials. Do not enable Actions debug logging unless the output has been reviewed for confidentiality.

## Artifacts and caches

The project workflows intentionally do not use `actions/upload-artifact` or `actions/cache`. APKs, reports, build directories, source archives, deployment packages, and project-derived caches are verified during the run and then discarded.

Toolchain-building workflows in this repository remain separate and may publish artifacts that contain only public tools and public dependency caches.

## Sanitized run receipts

`Report private project CI runs` records each completed `Run private project CI` or `Run Fichario CI` execution as a comment in the open **Public private CI run receipts** issue #15. This makes connector-triggered executions observable without requiring a general workflow-run listing API.

A receipt contains only:

- public workflow run ID and link;
- overall conclusion and trigger event;
- public branch and public workflow head SHA;
- public actor;
- selected project job name and conclusion.

It explicitly omits private source, private resolved commits, logs, artifacts, secrets, and build outputs. The reporter has only `actions: read` and `issues: write`; it receives no project token.

## Validation

Run before modifying the CI hub:

```bash
python3 scripts/test_private_ci_request.py
python3 scripts/test-private-ci-toolchain-policy.py
python3 scripts/test-semogsite-install-policy.py
python3 scripts/validate-private-ci-workflows.py
```

The public `Validate private CI hub` workflow also parses the YAML and runs these validators for relevant pushes and pull requests.

## Current limitations

- Project pushes do not automatically trigger this hub without a tiny dispatcher, a GitHub App, or an external webhook service.
- Results are not written back as commit statuses to project repositories.
- Build outputs are not published.
- Signing, Firebase secrets, TURN credentials, deployment, linked production databases, and production releases are outside these workflows.
