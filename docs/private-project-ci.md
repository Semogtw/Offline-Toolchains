# Public runner CI for private projects

The `Run private project CI` workflow performs the real verification and build workloads of selected private repositories as native runs of this public repository.

## Supported projects

| Project input | Private repository | Default ref | Commands executed |
| --- | --- | --- | --- |
| `goanime` | `Semogtw/goanime-mobile` | `main` | Flutter health, formatting, analysis, tests, release-workflow validation, debug APK build |
| `zapzap` | `Semogtw/Zapzap` | `development/android-build-recovery` | pure tests, source audit, Android baseline, unit tests, lint, debug APK build |
| `semogsite` | `Semogtw/SemogSite` | `develop/foundation-bootstrap` | frozen pnpm install, guardrails/typechecks/tests, production build |

The repository and commands are fixed in versioned code. Requests can select only a project key and a validated Git ref.

## Required secret

Create or update this Actions repository secret:

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

## Manual run

Open:

```text
Actions → Run private project CI → Run workflow
```

Select the project and optionally provide an exact branch, tag, or commit SHA. An empty ref uses the default from the table above.

## API dispatch

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

## Connector request branch

The connector-friendly path does not require `workflow_dispatch` support:

1. update `triggers/private-ci.json` on the permanent `build/private-ci` branch;
2. `Request private project CI` validates that request without private secrets;
3. a successful owner-authored request run triggers `Run private project CI` from the trusted default branch;
4. the privileged workflow reads the exact request revision and executes the matching project job.

Example request:

```json
{
  "project": "zapzap",
  "ref": "development/android-build-recovery"
}
```

Only the trigger JSON should normally change on `build/private-ci`. Do not develop workflow code on that branch.

## Public visibility

The workflow run, step names, exit status, requested ref, resolved commit SHA, and command output are public because the run belongs to a public repository. Project source is not uploaded automatically, but build tools and tests may print package names, file paths, test names, diagnostics, or stack traces.

Do not run refs that contain secrets in tracked files or tests that print credentials. Do not enable Actions debug logging for these runs unless the output has been reviewed for confidentiality.

## Artifacts and caches

The private-project workflow intentionally does not use `actions/upload-artifact` or `actions/cache`. APKs, reports, build directories, source archives, deployment packages, and project-derived caches are verified during the run and then discarded.

Toolchain-building workflows in this repository remain separate and may publish artifacts that contain only public tools and public dependency caches.

## Validation

Run before modifying the private CI flow:

```bash
python3 scripts/test_private_ci_request.py
python3 scripts/validate-private-ci-workflows.py
```

The public `Validate private CI hub` workflow also parses the YAML and runs both validators for relevant pushes and pull requests.

## Current limitations

- Private repository pushes do not automatically trigger this hub without a tiny private Actions dispatcher, a GitHub App, or an external webhook service.
- Results are not written back as commit statuses to the private repositories.
- Private build outputs are not published.
- Signing, Firebase secrets, TURN credentials, deployment, database migration, and production releases are outside this workflow.
