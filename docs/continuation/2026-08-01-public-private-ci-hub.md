# Public private-CI hub continuation

## Operational state

The public private-project CI hub is merged and active on `main`.

Completed infrastructure:

- `Run private project CI` executes the real GoAnime, ZapZap, and SemogSite workloads as native runs of the public `Semogtw/Offline-Toolchains` repository;
- `Request private project CI` accepts owner-authored requests from the permanent `build/private-ci` branch without exposing private-repository secrets;
- `PRIVATE_REPOSITORIES_TOKEN` is used only for allowlisted, shallow, non-persistent private checkouts;
- project outputs, APKs, reports, source archives, and project-derived Actions caches are not uploaded;
- issue #15 receives sanitized completion receipts without private source, private resolved SHAs, logs, artifacts, secrets, or build outputs;
- the validation workflow enforces request mappings, project commands, checkout restrictions, Java runtime policy, and SemogSite dependency-install policy.

## Verified execution path

All three private repositories have completed the entire routing path into their real public-runner project jobs:

- ZapZap reached its pure JVM suite and source-audit gates;
- SemogSite reached Corepack and pnpm dependency installation;
- GoAnime reached project health and Dart formatting verification.

The initial red runs exposed project-level defects rather than a failure to execute private workloads in the public repository.

## Active project follow-ups

### ZapZap

PR `Semogtw/Zapzap#29` fixes portable Kotlin runtime discovery for symlinked launchers. The public hub uses JDK 21 for the canonical Android gate while the project continues targeting Java/Kotlin bytecode 17. Validate the final PR head through `build/private-ci` before merging it into `development/android-build-recovery`.

### SemogSite

PR `Semogtw/SemogSite#8` replaces the unpublished `@tanstack/router-cli@^1.168.32` request with the published `1.167.21` release. The central workflow now uses frozen pnpm installs when a lockfile exists and the project's documented bootstrap mode only while the lockfile is absent. Validate install, `pnpm check`, and `pnpm build` before merging.

### GoAnime

The first public run passed private checkout, JDK/Android/Flutter setup, dependency resolution, and project health, then failed the formatting gate. A new run against the current `main` was requested because the private branch advanced with formatting commits after the first result. Do not weaken or remove the formatter gate; fix remaining source formatting in the private repository if the current head still fails.

## Request procedure

Change only `triggers/private-ci.json` on `build/private-ci`:

```json
{
  "project": "zapzap",
  "ref": "exact-branch-tag-or-commit"
}
```

Prefer an exact commit SHA when validating a pull request head. Inspect issue #15 for the sanitized completion receipt, then use the public workflow's job steps and logs to diagnose failures.

## Security invariants

Do not:

- broaden the repository allowlist from event payloads;
- accept commands, scripts, runner labels, artifact paths, or repositories from `client_payload`;
- enable `persist-credentials` for private checkouts;
- expose or propagate `PRIVATE_REPOSITORIES_TOKEN` to project commands;
- upload private build outputs or source-derived caches from the public workflow;
- merge project fixes without rerunning their exact final head through the public hub.
