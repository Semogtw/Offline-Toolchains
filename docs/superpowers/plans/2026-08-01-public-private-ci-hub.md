# Public Runner Project CI Hub Implementation Plan

> **For agentic workers:** use `superpowers:executing-plans` or an equivalent task-by-task workflow. Preserve small commits and verify contracts before changing the permanent request branch.

**Goal:** Maintain secure public-repository workflows that execute canonical verification for allowlisted private projects and the public `Semogtw/FicharioVirtual` repository.

**Architecture:** A no-secret request workflow validates connector-written JSON on `build/private-ci`. Private projects run in a token-scoped workflow. Fichário runs in a separate token-free workflow. A static validator, public validation workflow and sanitized issue receipts enforce and expose the operational contract.

**Tech Stack:** GitHub Actions YAML, Bash, Python 3, Flutter, JDK/Android, Node.js, pnpm, Playwright, Deno, Supabase CLI and Docker-backed local services.

## Global constraints

- Heavy verification runs belong to `Semogtw/Offline-Toolchains`.
- Allowlisted repositories are fixed in code:
  - `Semogtw/goanime-mobile`;
  - `Semogtw/Zapzap`;
  - `Semogtw/SemogSite`;
  - `Semogtw/FicharioVirtual`.
- Payloads may select only an allowlisted project and validated Git ref.
- `PRIVATE_REPOSITORIES_TOKEN` is read-only, checkout-only and never exposed to Fichário.
- Project workflows upload no source, build, report or project-derived cache artifact.
- All checkouts disable credential persistence, LFS and submodules and are deleted in `always()` cleanup.

---

## Implemented foundation

### Request validation library

- `scripts/private_ci_request.py` maps project keys to fixed repositories/default refs.
- `scripts/test_private_ci_request.py` covers mappings, valid refs and rejected payloads.
- `triggers/private-ci.json` on `build/private-ci` is the only normal connector mutation surface.

### Connector request workflow

`Request private project CI`:

- accepts only owner-authored pushes on `build/private-ci` changing the trigger JSON;
- checks out trusted validator code from `main`;
- checks out only the exact request file from the request revision;
- has no private secret and runs no project source.

### Private execution workflow

`Run private project CI` retains fixed jobs for:

- GoAnime: health, formatting, analysis, tests, release workflow validation and debug APK;
- ZapZap: pure/source/baseline gates, Android unit tests, lint and debug APK;
- SemogSite: dependency install policy, `pnpm check` and `pnpm build`.

### Static contract and receipts

- `scripts/validate-private-ci-workflows.py` enforces mappings, commands, trust checks, checkout flags and output restrictions.
- `Report private project CI runs` writes sanitized completion receipts to issue #15.

---

## Fichário extension

### Task 1: Allowlist the public repository

**Files:**
- Modify: `scripts/private_ci_request.py`
- Modify: `scripts/test_private_ci_request.py`

- [x] Add `fichario` mapped exactly to `Semogtw/FicharioVirtual` and default `main`.
- [x] Add a regression test that rejects any payload attempt to replace the repository.

### Task 2: Add a separate token-free workflow

**Files:**
- Create: `.github/workflows/run-fichario-ci.yml`

- [x] Accept manual exact refs and trusted successful request-workflow events.
- [x] Reuse the trusted request validator from `main`.
- [x] Require normalized project `fichario` before starting the verification job.
- [x] Fix checkout repository to `Semogtw/FicharioVirtual`.
- [x] Disable persisted credentials, LFS and submodules.
- [x] Install pnpm 10 and Node.js 22.16.
- [x] Install frozen dependencies and Chromium with host packages.
- [x] Install Deno 2.8.1 and Supabase CLI.
- [x] Run only `pnpm verify:full`.
- [x] Remove checkout in `always()` cleanup and upload no artifacts.

### Task 3: Extend static security contracts

**Files:**
- Modify: `scripts/validate-private-ci-workflows.py`

- [x] Require the Fichário workflow, fixed repository, exact tool setup and canonical aggregate command.
- [x] Forbid private token/secrets, artifact upload, caches, persistent credentials and payload-controlled commands.
- [x] Keep existing private workflow counts and boundaries unchanged.

### Task 4: Extend sanitized receipts

**Files:**
- Modify: `.github/workflows/report-private-project-ci-runs.yml`

- [x] Observe `Run Fichario CI` completion.
- [x] Include `Fichário Virtual complete verification` in recognized project jobs.
- [x] Preserve omission of source, resolved private SHA, logs, artifacts, secrets and outputs.

### Task 5: Document operations and architecture

**Files:**
- Modify: `docs/private-project-ci.md`
- Modify: `docs/superpowers/specs/2026-08-01-public-private-ci-hub-design.md`
- Modify: this plan

- [x] Document `fichario`, `Semogtw/FicharioVirtual`, token-free separation and `pnpm verify:full`.

### Task 6: Verify the hub contract

- [ ] Reconstruct or check out the public hub files in a runnable environment.
- [ ] Run:

```bash
python3 scripts/test_private_ci_request.py
python3 scripts/test-private-ci-toolchain-policy.py
python3 scripts/test-semogsite-install-policy.py
python3 scripts/validate-private-ci-workflows.py
```

- [ ] Parse all changed workflow YAML.
- [ ] Run Bash syntax checks for every new `run:` block where applicable.
- [ ] Fix the first concrete failure before changing the request branch.

### Task 7: Request exact Fichário HEAD verification

- [ ] Resolve the latest `Semogtw/FicharioVirtual@main` SHA.
- [ ] Update only `triggers/private-ci.json` on `build/private-ci`:

```json
{
  "project": "fichario",
  "ref": "<exact-40-character-sha>"
}
```

- [ ] Observe request and execution receipts in issue #15.
- [ ] Use the public run ID to inspect the first failing job/step if the run is red.
- [ ] Apply code fixes in Fichário and repeat with the new exact SHA until the canonical gate is green or an external blocker is proven.

### Task 8: Record evidence and remove dead project-local CI

- [ ] Update Fichário validation documentation with exact SHA, run ID, commands and conclusion.
- [ ] Remove the unobservable `.github/workflows/validate-current-head.yml` from Fichário after the hub path is proven.
- [ ] Never reuse the historical green checkpoint as evidence for a later HEAD.
