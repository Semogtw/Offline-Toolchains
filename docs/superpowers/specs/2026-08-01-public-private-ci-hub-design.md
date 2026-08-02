# Public Runner Project CI Hub Design

## Status

Approved for implementation by the repository owner on 2026-08-01. Extended on 2026-08-02 to validate the public Fichário Virtual repository through the same connector request bridge.

## Goal

Run real verification and build workloads as native GitHub Actions runs of the public `Semogtw/Offline-Toolchains` repository. Private projects use public hosted-runner allowance after an allowlisted read-only checkout. Public projects may reuse the request and receipt infrastructure without receiving private-repository credentials.

## Scope

| Project key | Repository | Default ref | Real workload |
| --- | --- | --- | --- |
| `goanime` | `Semogtw/goanime-mobile` | `main` | project health, formatting, analysis, tests, release-workflow validation, debug APK build |
| `zapzap` | `Semogtw/Zapzap` | `development/android-build-recovery` | pure tests, source audit, Android baseline, unit tests, lint, debug APK build |
| `semogsite` | `Semogtw/SemogSite` | `develop/foundation-bootstrap` | dependency installation, guardrails/typechecks/tests, production build |
| `fichario` | `Semogtw/FicharioVirtual` | `main` | frozen dependency install and the canonical `pnpm verify:full` gate with browser, Deno, Supabase CLI and local database services |

No event payload may choose an arbitrary repository, shell command, workflow path, artifact path, secret, or runner label.

## Selected architecture

### Trusted request bridge

`Request private project CI` validates `triggers/private-ci.json` on the permanent `build/private-ci` branch. The request contains only an allowlisted project key and optional exact Git ref:

```json
{
  "project": "fichario",
  "ref": "0123456789abcdef0123456789abcdef01234567"
}
```

The request workflow:

- has only `contents: read`;
- receives no project checkout token;
- checks out the validator from trusted `main`;
- checks out only the trigger JSON from the exact request revision;
- accepts only owner-authored pushes from the fixed request branch.

### Private execution workflow

`Run private project CI` handles `goanime`, `zapzap`, and `semogsite`. It maps each key to a fixed private repository and canonical commands. Private checkout uses `PRIVATE_REPOSITORIES_TOKEN` only in `actions/checkout`, with credential persistence, LFS, and submodules disabled. No project artifact or project-derived cache is uploaded, and the checkout is removed in `always()` cleanup.

The fine-grained token is read-only and scoped only to:

- `Semogtw/goanime-mobile`;
- `Semogtw/Zapzap`;
- `Semogtw/SemogSite`.

### Public Fichário execution workflow

`Run Fichario CI` is a separate workflow. Separation is intentional:

- it never receives `PRIVATE_REPOSITORIES_TOKEN` or any secret;
- repository identity is fixed to `Semogtw/FicharioVirtual`;
- only a normalized request with project `fichario` can start the verification job;
- checkout remains shallow and non-persistent;
- setup is fixed to Node.js 22.16, pnpm 10, Chromium, Deno 2.8.1 and Supabase CLI;
- dependency installation is frozen;
- the only project command is `pnpm verify:full`;
- build outputs and source archives are not uploaded;
- the checkout is removed in `always()` cleanup.

The separate workflow keeps public validation independent from the private token boundary and avoids expanding the privileged workflow's command surface.

### Sanitized receipts

`Report private project CI runs` observes both execution workflows and appends a sanitized receipt to issue #15. Receipts include public run metadata and selected job conclusion, but omit private source, resolved private commit, logs, artifacts, secrets and build outputs.

## Trigger validation

The validator accepts only `goanime`, `zapzap`, `semogsite`, and `fichario`. Refs must be 1–200 characters, use Git-ref-safe ASCII, and reject whitespace, control characters, `..`, `@{`, backslashes, leading hyphens, double slashes, trailing slashes and `.lock` suffixes.

The payload cannot override repository, runner, script, command, environment, secret or output destination.

## Project execution

### GoAnime

- Flutter 3.44.1;
- project health and release workflow validation;
- formatting, analysis and tests;
- Android debug APK build.

### ZapZap

- Temurin JDK 21 with Android target compatibility preserved by the project;
- Android SDK 35;
- pure tests, source audit and Android baseline;
- unit tests, lint and debug APK build.

### SemogSite

- Node.js 22;
- repository-selected pnpm through Corepack;
- frozen installation when a lockfile exists, documented bootstrap mode otherwise;
- `pnpm check` and `pnpm build`.

### Fichário Virtual

- Node.js 22.16 and pnpm 10;
- `pnpm install --frozen-lockfile`;
- Chromium plus host dependencies for Playwright;
- Deno checks for Supabase Edge Functions;
- Supabase CLI and Docker-backed local database services;
- `pnpm verify:full`, covering frontend lint/typecheck/tests/build, E2E, source security, migration/RPC guards, Edge Function type checks, database reset, pgTAP, OCR concurrency and UTC rollover gates.

No deployment, production secret, linked production database, billing change or release publication occurs.

## Failure handling

Invalid requests fail before project checkout. Missing private token affects only private jobs. Project command failures propagate as failed public runs. Cleanup always executes. No retry loop hides deterministic failures.

## Verification

Repository-local validators enforce:

- fixed project mappings and refs;
- trusted request-branch conditions;
- exact checkout flags and commands;
- private token absence from the Fichário workflow;
- no artifact/cache upload from project workflows;
- receipt coverage and documentation coverage.

The public validation workflow parses YAML and runs request, policy and workflow-contract tests.

## Out of scope

- arbitrary repositories or commands;
- automatic project push webhooks without a dispatcher;
- writing statuses back to project commits;
- private build artifact publication;
- signing, production deployment or production secrets;
- linked production Supabase validation.
