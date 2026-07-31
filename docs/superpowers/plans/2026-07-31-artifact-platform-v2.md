# Artifact Platform v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible, connector-friendly platform for exact private-lock toolchains, encrypted workspace restoration, artifact reuse, cleanup, catalogs, diagnostics and compatibility enforcement.

**Architecture:** JSON profile descriptors and a schema-v2 artifact contract define every package. Secret-free request workflows validate data; default-branch privileged workflows use the existing read-only PAT only for fixed private repositories, prove offline resolution, delete source and upload public caches. Local Python/Bash tools validate, assemble, decrypt, restore and diagnose without network access.

**Tech Stack:** Bash 5, Python 3 standard library, Git, GnuPG, tar/zstd, unzip, GitHub Actions, `gh` CLI on hosted runners, Flutter 3.44.1, Temurin JDK 17/21, Gradle 8.9/8.14, Android SDK 35/36.

## Global Constraints

- Source artifacts remain encrypted to OpenPGP fingerprint `2DE29DC31427CF0A911AB96175679291435059B0`.
- The private key never enters GitHub, repository history, Actions secrets or artifacts.
- `PRIVATE_REPOSITORIES_TOKEN` remains read-only and limited to GoAnime Mobile and ZapZap.
- Private repository mappings are fixed; no arbitrary repository input is accepted.
- Artifact payload parts are at most `400 MiB`; connector ZIPs must remain below `512 MiB`.
- Artifact retention is one day.
- Schema version is `2`.
- Supported restoration host is `linux/x86_64`.
- Public synthetic artifacts are never accepted as exact-lock proof.
- Source-bundle artifacts are excluded from toolchain cleanup.

---

### Task 1: Artifact contract and profile registry

**Files:**
- Create: `schemas/artifact-set-v2.schema.json`
- Create: `schemas/toolchain-request-v1.schema.json`
- Create: `profiles/android-base.json`
- Create: `profiles/jdk21.json`
- Create: `profiles/goanime-analysis.json`
- Create: `profiles/goanime-android.json`
- Create: `profiles/goanime-full.json`
- Create: `profiles/zapzap-pure.json`
- Create: `profiles/zapzap-android.json`
- Create: `profiles/zapzap-full.json`
- Create: `scripts/lib/artifact_contract.py`
- Create: `scripts/lib/profile_registry.py`
- Create: `tests/test_artifact_contract.py`
- Create: `tests/test_profile_registry.py`

**Interfaces:**
- Produces `validate_manifest(document: dict) -> list[str]`.
- Produces `compute_fingerprint(parts: list[bytes]) -> str`.
- Produces `load_profiles(root: Path) -> dict[str, dict]`.
- Produces `expand_profile(name: str, registry: dict[str, dict]) -> list[str]`.

- [ ] **Step 1: Add failing contract/profile tests**

Tests cover required manifest fields, SHA-256 format, supported architecture, duplicate/cyclic requirements and deterministic dependency order.

- [ ] **Step 2: Verify the tests fail**

Run:

```bash
python3 -m unittest tests.test_artifact_contract tests.test_profile_registry -v
```

Expected: import/file failures.

- [ ] **Step 3: Implement schemas, descriptors and standard-library validators**

Descriptors must include `name`, `kind`, `project`, `packages`, `requires`, `activation_order`, `lock_mode`, `lock_inputs`, `doctor_checks`, `platform` and `architecture`.

- [ ] **Step 4: Verify tests pass**

```bash
python3 -m unittest tests.test_artifact_contract tests.test_profile_registry -v
```

- [ ] **Step 5: Commit**

```bash
git add schemas profiles scripts/lib tests
 git commit -m "feat: define artifact contract and profiles"
```

### Task 2: Uniform packager, inventory and doctor

**Files:**
- Create: `scripts/build_artifact_set.py`
- Create: `scripts/doctor.sh`
- Create: `scripts/assemble-artifact.sh`
- Modify: `scripts/assemble-source-bundle.sh`
- Create: `tests/test_build_artifact_set.py`
- Create: `tests/test_doctor.py`
- Create: `tests/fixtures/tiny-package/`

**Interfaces:**
- `build_artifact_set.py package --profile <name> --package <name> --root <dir> --archive <path> --lock-fingerprint <sha256> --builder-fingerprint <sha256> --software <json> --out <dir>`.
- `assemble-artifact.sh <downloads-dir> <manifest-json> <output-archive>`.
- `doctor.sh --manifest <artifact-set.json> [--root <dir>] [--json]`.

- [ ] **Step 1: Add failing package/doctor tests**

Tests assert deterministic part ordering, relative checksums, SPDX 2.3 JSON generation, 400 MiB configuration, JSON doctor states and checksum failures.

- [ ] **Step 2: Run failing tests**

```bash
python3 -m unittest tests.test_build_artifact_set tests.test_doctor -v
```

- [ ] **Step 3: Implement packager and generic assembler**

The packager writes `artifact-set.json`, `SBOM.spdx.json`, `PARTS.txt`, `SHA256SUMS.parts`, copies `doctor.sh`, creates `.tar.zst`, splits with numeric suffixes and never writes absolute checksum paths.

- [ ] **Step 4: Implement doctor checks**

Supported check types: `executable`, `version_contains`, `directory`, `file`, `environment`, and `command_optional`. JSON output includes `status`, `checks`, `profile`, `package`, `lock_fingerprint` and `errors`.

- [ ] **Step 5: Make source assembly a compatibility wrapper**

`assemble-source-bundle.sh` delegates transport validation to `assemble-artifact.sh` while preserving its existing CLI.

- [ ] **Step 6: Run tests and shell syntax checks**

```bash
python3 -m unittest tests.test_build_artifact_set tests.test_doctor -v
bash -n scripts/assemble-artifact.sh scripts/assemble-source-bundle.sh scripts/doctor.sh
```

- [ ] **Step 7: Commit**

```bash
git add scripts tests
 git commit -m "feat: add uniform artifact packaging and doctor"
```

### Task 3: One-command workspace restoration

**Files:**
- Create: `scripts/restore-workspace.sh`
- Create: `scripts/restore_workspace.py`
- Create: `tests/test_restore_workspace.py`
- Create: `tests/fixtures/manifests/`

**Interfaces:**
- CLI:

```text
scripts/restore-workspace.sh --project goanime|zapzap --downloads DIR --private-key FILE --destination DIR --profile PROFILE [--branch REF] [--require-exact-lock] [--keep-temporary]
```

- Python engine functions: `safe_extract_zip`, `safe_extract_tar`, `verify_key_fingerprint`, `restore_git_bundle`, `validate_compatibility`, `write_activation_script`, `write_restore_report`.

- [ ] **Step 1: Add failing fixture tests**

Cover successful tiny encrypted bundle restoration, ZIP traversal, tar traversal, mixed artifact-set IDs, wrong key fingerprint, unsupported schema, wrong architecture, profile dependency ordering and cleanup trap behavior.

- [ ] **Step 2: Run failing tests**

```bash
python3 -m unittest tests.test_restore_workspace -v
```

- [ ] **Step 3: Implement the Python restoration engine**

Use only standard library plus external binaries checked by preflight. Never `source` downloaded scripts during validation. Validate paths before extraction.

- [ ] **Step 4: Implement Bash wrapper and cleanup trap**

The wrapper resolves its repository root, validates arguments and executes the Python engine. Default cleanup removes ZIPs only when they are inside the declared downloads staging directory; it never removes the user-supplied private key.

- [ ] **Step 5: Verify end-to-end fixture restoration**

```bash
python3 -m unittest tests.test_restore_workspace -v
bash -n scripts/restore-workspace.sh
```

- [ ] **Step 6: Commit**

```bash
git add scripts tests
 git commit -m "feat: restore encrypted workspaces in one command"
```

### Task 4: Connector request and exact-lock builder

**Files:**
- Create: `triggers/toolchain-build.json`
- Create: `scripts/validate-toolchain-request.py`
- Create: `.github/workflows/request-toolchain-build.yml`
- Create: `.github/workflows/build-exact-toolchain.yml`
- Create: `scripts/collect-lock-inputs.py`
- Create: `scripts/render-software-inventory.py`
- Create: `tests/test_toolchain_request.py`
- Create: `tests/test_lock_inputs.py`

**Interfaces:**
- Request JSON: `{ "profile": "goanime-analysis", "force_rebuild": false }`.
- Validator output file: `validated-request.json` containing only registry-derived project/repository/profile data.
- Lock collector output: `lock-inputs.json`, `lock-fingerprint.txt`, `software.json`.

- [ ] **Step 1: Add failing request/lock tests**

Reject arbitrary repositories, aggregate profiles at the concrete builder boundary, unknown fields, refs, path traversal and symlinked lock inputs.

- [ ] **Step 2: Implement secret-free request validation**

The request workflow runs on `build/toolchains`, checks actor/event/branch and uploads only the validated request as a short-lived internal artifact.

- [ ] **Step 3: Implement privileged builder boundary**

The workflow is loaded from `main`, verifies the preceding workflow conclusion/event/head branch/actor, maps project keys internally and performs checkout with `fetch-depth: 0`, `persist-credentials: false`, `lfs: false`, `submodules: false`.

- [ ] **Step 4: Implement GoAnime exact hydration**

Run online `flutter pub get --enforce-lockfile`, profile-specific warmup, then `flutter pub get --offline --enforce-lockfile`; package only Flutter/Pub/Gradle/PowerShell roots selected by profile. Delete checkout before upload.

- [ ] **Step 5: Implement ZapZap exact hydration**

Use Temurin 21, project-scoped Gradle cache and profile tasks. Repeat the selected tasks with `--offline`; package only public caches/tooling. Delete checkout before upload.

- [ ] **Step 6: Produce schema-v2 package sets**

Call `build_artifact_set.py` for every concrete package, with `lock_mode=private-exact` and exact lock fingerprint.

- [ ] **Step 7: Run tests and workflow guards**

```bash
python3 -m unittest tests.test_toolchain_request tests.test_lock_inputs -v
bash scripts/validate-private-source-workflows.sh
python3 scripts/validate-toolchain-request.py --request triggers/toolchain-build.json --profiles profiles
```

- [ ] **Step 8: Commit**

```bash
git add triggers scripts tests .github/workflows
 git commit -m "feat: build exact private-lock toolchains"
```

### Task 5: Catalog, reuse and cleanup

**Files:**
- Create: `scripts/catalog_artifacts.py`
- Create: `.github/workflows/report-toolchain-runs.yml`
- Create: `tests/test_catalog_artifacts.py`
- Modify: `.github/workflows/build-exact-toolchain.yml`
- Modify: public builder workflows as integrated in Task 6

**Interfaces:**
- `catalog_artifacts.py render --run-json FILE --artifacts-json FILE`.
- `catalog_artifacts.py find-reusable --profile NAME --fingerprint SHA --artifacts-json FILE`.
- `catalog_artifacts.py select-cleanup --current-run ID --artifacts-json FILE --now ISO8601`.

- [ ] **Step 1: Add failing catalog/reuse/cleanup tests**

Fixtures cover complete set reuse, missing part, expired part, different lock fingerprint, current-run preservation, source-prefix exclusion, unrelated-profile preservation and six-hour orphan cleanup.

- [ ] **Step 2: Implement catalog rendering and marker replacement**

One issue comment per profile uses marker `<!-- toolchain-profile:<name> -->`; source receipts continue in issue #4.

- [ ] **Step 3: Implement pre-build reuse lookup**

Use `gh api` with `actions: read`. Reuse requires a valid manifest artifact and all expected parts. Emit `reuse-receipt.json` and skip hydration/upload.

- [ ] **Step 4: Implement post-build cleanup**

Reporter uses `actions: write` and deletes only IDs selected by the tested dry-run algorithm. It records deleted bytes and failures in the catalog comment.

- [ ] **Step 5: Run tests**

```bash
python3 -m unittest tests.test_catalog_artifacts -v
```

- [ ] **Step 6: Commit**

```bash
git add scripts tests .github/workflows
 git commit -m "feat: catalog reuse and clean artifact sets"
```

### Task 6: Retrofit public builders and lightweight profiles

**Files:**
- Modify: `.github/workflows/build-android-base.yml`
- Modify: `.github/workflows/build-jdk21.yml`
- Modify: `.github/workflows/build-goanime.yml`
- Modify: `.github/workflows/build-zapzap.yml`
- Create: `scripts/validate-workflows.py`
- Create: `tests/test_workflow_contracts.py`

**Interfaces:**
- Every public builder calls `build_artifact_set.py`.
- Every artifact name follows `<profile>-<fingerprint16>-<run_id>-manifest|part-NN`.
- Synthetic builders set `lock_mode=synthetic`.

- [ ] **Step 1: Add failing workflow-contract tests**

Check one-day retention, 400 MiB splitting, schema-v2 packager call, doctor inclusion, relative checksums, explicit profile, no secrets and no private checkout.

- [ ] **Step 2: Retrofit Android and JDK builders**

Publish `android-base` and `jdk21` package sets with software inventory and version checks.

- [ ] **Step 3: Split GoAnime capabilities**

Public workflow accepts `goanime-analysis` or `goanime-android` manual input and defaults to analysis for PR validation. The persistent build trigger may request aggregate profiles through the exact builder instead of creating a mega-archive.

- [ ] **Step 4: Split ZapZap capabilities**

Public workflow accepts `zapzap-pure` or `zapzap-android`, uses JDK 21 for current Gradle validation and records synthetic lock mode.

- [ ] **Step 5: Run workflow tests and YAML parse**

```bash
python3 -m unittest tests.test_workflow_contracts -v
python3 scripts/validate-workflows.py .github/workflows
```

- [ ] **Step 6: Commit**

```bash
git add .github/workflows scripts tests
 git commit -m "refactor: publish profile-based toolchain artifacts"
```

### Task 7: Documentation and connector operating surface

**Files:**
- Modify: `README.md`
- Create: `docs/ARTIFACT_CONTRACT.md`
- Create: `docs/RESTORE_WORKSPACE.md`
- Create: `docs/PROFILE_REGISTRY.md`
- Modify: `scripts/validate-private-source-workflows.sh`
- Modify: `triggers/build.txt` documentation or replace with request guidance

- [ ] **Step 1: Document profiles and exact versus synthetic modes**

Include activation order, required artifact families, lock fingerprint semantics and product-evidence boundary.

- [ ] **Step 2: Document one-command restoration**

Provide exact connector request, download, restore and cleanup instructions without private-key contents.

- [ ] **Step 3: Document catalog/reuse/cleanup**

Explain issue markers, expiry, artifact IDs and safe deletion rules.

- [ ] **Step 4: Extend security guard**

Reject private-key blocks, arbitrary repository inputs, artifact retention above one day, part sizes above 400 MiB, missing source deletion and request workflows that receive secrets.

- [ ] **Step 5: Run documentation/security validation**

```bash
bash scripts/validate-private-source-workflows.sh
python3 -m unittest discover -s tests -v
```

- [ ] **Step 6: Commit**

```bash
git add README.md docs scripts triggers
 git commit -m "docs: explain artifact platform v2"
```

### Task 8: End-to-end hosted validation

**Files:**
- Temporary then delete: `.github/workflows/export-workspace-for-agent.yml`
- Update: implementation report in PR body or `docs/superpowers/reports/2026-07-31-artifact-platform-v2.md`

- [ ] **Step 1: Run all secret-free PR checks**

Expected: contracts, restore fixtures, workflow guards and shell syntax pass.

- [ ] **Step 2: Trigger public concrete profiles**

Validate manifest + parts are connector-downloadable and doctor reports `ready` after local reconstruction.

- [ ] **Step 3: Trigger GoAnime exact profile**

Expected: private checkout, exact lock fingerprint, online hydration, `flutter pub get --offline --enforce-lockfile`, source deletion and schema-v2 upload succeed.

- [ ] **Step 4: Trigger ZapZap exact profile**

Expected: JDK 21, Gradle 8.9 profile tasks rerun with `--offline`, source deletion and schema-v2 upload succeed.

- [ ] **Step 5: Trigger identical request again**

Expected: reusable set found; no dependency hydration; catalog marks reuse.

- [ ] **Step 6: Validate local restore**

Download source and toolchain sets through the connector, run `restore-workspace.sh`, run `doctor.sh --json`, verify Git and execute focused offline gates.

- [ ] **Step 7: Validate cleanup**

Confirm older equivalent sets are deleted, current/source/unrelated artifacts remain, and deletion is reported.

- [ ] **Step 8: Remove temporary export workflow and commit report**

```bash
git add -A
 git commit -m "test: verify artifact platform end to end"
```

### Task 9: Final verification and integration

**Files:**
- All changed files

- [ ] **Step 1: Run complete local suite**

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh
bash scripts/validate-private-source-workflows.sh
python3 scripts/validate-workflows.py .github/workflows
```

- [ ] **Step 2: Inspect diff for secrets and private source**

```bash
git diff --check main...HEAD
git grep -n 'BEGIN PGP PRIVATE KEY\|PRIVATE_REPOSITORIES_TOKEN=' -- . ':!docs/superpowers/plans/*'
```

Expected: no private-key block or assigned token value.

- [ ] **Step 3: Verify branch relationship**

```bash
git rev-list --left-right --count main...HEAD
```

Expected: zero commits behind after functional rebase if main advanced.

- [ ] **Step 4: Commit any final corrections and update PR**

The PR remains draft until both exact-profile hosted validations and connector restoration succeed.
