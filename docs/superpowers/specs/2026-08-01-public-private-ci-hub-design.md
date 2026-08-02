# Public Runner Private CI Hub Design

## Status

Approved for implementation by the repository owner on 2026-08-01.

## Goal

Run the real verification and build workloads for selected private repositories as native GitHub Actions runs of the public `Semogtw/Offline-Toolchains` repository, so the expensive jobs use the public repository's hosted-runner allowance rather than the private repositories' Actions minutes.

## Scope

The first version supports exactly three allowlisted projects:

| Project key | Private repository | Default ref | Real workload |
| --- | --- | --- | --- |
| `goanime` | `Semogtw/goanime-mobile` | `main` | project health, formatting, analysis, tests, release-workflow validation, debug APK build |
| `zapzap` | `Semogtw/Zapzap` | `development/android-build-recovery` | pure tests, source audit, Android baseline, unit tests, lint, debug APK build |
| `semogsite` | `Semogtw/SemogSite` | `develop/foundation-bootstrap` | frozen install, guardrails/typecheck/tests through `pnpm check`, production build |

No arbitrary repository, shell command, workflow path, artifact path, or runner label may be supplied by an event payload.

## Considered approaches

### Reusable workflows called from private repositories

Rejected because the run and billing context remain attached to the private caller repository.

### Tiny private dispatch workflows plus public execution

Technically valid, but every push still starts a private-repository run and consumes at least a small amount of its Actions allowance. This can be added later when automatic push triggering is more important than zero private Actions use.

### Native public workflows with manual, API, and connector request triggers

Selected. The privileged workflow belongs to `Offline-Toolchains`, checks out an allowlisted private repository by exact ref, and executes all meaningful work in the public runner. Manual `workflow_dispatch`, authenticated `repository_dispatch`, and a trusted request-branch bridge are supported.

## Architecture

### Request layer without private secrets

`Request private project CI` validates `triggers/private-ci.json` on the permanent `build/private-ci` branch. The file contains only:

```json
{
  "project": "zapzap",
  "ref": "development/android-build-recovery"
}
```

The request workflow has `contents: read`, never receives the private-repository token, and executes no project code. Its successful `workflow_run` is accepted only when the request came from the fixed branch, a push event, and the repository owner.

### Privileged execution layer

`Run private project CI` is stored on the default branch and handles:

- `workflow_dispatch` with project and ref inputs;
- `repository_dispatch` events with fixed event type `private-project-ci`;
- successful trusted `workflow_run` events from the request workflow.

A normalization job validates the request and maps the project key to a fixed repository and default ref. Three project-specific jobs then perform setup, checkout the selected private ref with `persist-credentials: false`, and run the canonical project commands.

### Isolation

Each project job:

- receives only the normalized project/ref/repository outputs;
- uses a fresh GitHub-hosted Ubuntu runner;
- has `contents: read` on the public repository;
- uses `PRIVATE_REPOSITORIES_TOKEN` only during private checkout;
- disables credential persistence, LFS, and submodules;
- does not upload artifacts, caches containing project outputs, logs, test reports, APKs, source archives, or build directories;
- removes the private checkout in an `always()` cleanup step.

The token must be a fine-grained PAT with `Contents: Read-only` for only `goanime-mobile`, `Zapzap`, and `SemogSite`.

## Trigger data validation

The validator accepts only the three project keys. Refs must be 1-200 characters, use Git ref-safe ASCII characters, and reject whitespace, control characters, `..`, `@{`, backslashes, leading hyphens, double slashes, trailing slashes, and `.lock` suffixes.

The event payload cannot select a repository, runner, script, command, environment, secret, or output destination.

## Project execution

### GoAnime

- Flutter `3.44.1`, stable channel;
- `flutter pub get`;
- `pwsh ./tools/validate_project_health.ps1`;
- `dart format --output=none --set-exit-if-changed lib test packages tools`;
- `flutter analyze --no-pub`;
- `flutter test --no-pub`;
- `pwsh ./tools/validate_release_workflows.ps1`;
- `flutter build apk --debug --no-pub`.

### ZapZap

- Temurin JDK 17;
- Android SDK platform 35 and build tools required by the checked-out project;
- Gradle caches disabled at the Actions integration layer;
- `bash ./tools/checks/run_pure_tests.sh`;
- `bash ./tools/checks/audit_sources.sh`;
- `bash ./tools/checks/verify_android_baseline.sh`;
- `./gradlew --no-daemon testDebugUnitTest`;
- `./gradlew --no-daemon lintDebug`;
- `./gradlew --no-daemon :app:assembleDebug`.

The first public CI run may use the network to populate Gradle dependencies. Deterministic offline execution remains a separate toolchain validation concern.

### SemogSite

- Node.js 22;
- Corepack activates the exact `packageManager` declared by the checked-out `package.json`;
- `pnpm install --frozen-lockfile`;
- `pnpm check`;
- `pnpm build`.

No deployment, database migration, secrets-backed integration test, or Playwright browser installation is part of this first CI hub version.

## Failure handling

Invalid requests fail before private checkout. Missing token fails with a concise message. Project command failures propagate as failed public runs. Cleanup runs even after failure. No retry loop hides deterministic failures.

## Verification

A repository-local validator checks the workflow contract without secrets. It verifies fixed mappings, fixed commands, safe checkout options, absence of artifact upload, request-branch trust checks, and documentation coverage. A public validation workflow runs this script for relevant pushes and pull requests.

## Out of scope

- automatic push webhooks without any private Actions run;
- writing commit statuses back to private repositories;
- publishing private build artifacts;
- release signing, Firebase configuration, TURN credentials, deployment, or production releases;
- arbitrary additional private repositories.
