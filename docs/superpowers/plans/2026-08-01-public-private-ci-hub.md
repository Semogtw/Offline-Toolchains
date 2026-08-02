# Public Runner Private CI Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secure native public-repository workflows that execute the real CI and debug-build workloads of GoAnime, ZapZap, and SemogSite after an allowlisted private checkout.

**Architecture:** A no-secret request workflow validates connector-written JSON on `build/private-ci`. A privileged workflow on the default branch normalizes manual, API, or trusted workflow-run requests and dispatches one of three project-specific jobs. A static validator and public validation workflow enforce the security contract.

**Tech Stack:** GitHub Actions YAML, Bash, Python 3 standard library, Flutter 3.44.1, JDK 17, Android SDK 35, Gradle, Node.js 22, Corepack, pnpm.

## Global Constraints

- Heavy verification and build commands must execute as runs of `Semogtw/Offline-Toolchains`.
- Supported repositories are exactly `Semogtw/goanime-mobile`, `Semogtw/Zapzap`, and `Semogtw/SemogSite`.
- `PRIVATE_REPOSITORIES_TOKEN` is read-only and is never persisted by checkout.
- No private source, APK, build directory, test report, source archive, or project-derived cache is uploaded from the public workflow.
- Event payloads may select only an allowlisted project key and a validated Git ref.
- All project checkouts use `lfs: false`, `submodules: false`, and `persist-credentials: false`.

---

### Task 1: Request validation library

**Files:**
- Create: `scripts/private_ci_request.py`
- Create: `scripts/test_private_ci_request.py`

**Interfaces:**
- Consumes: JSON request containing `project` and optional `ref`.
- Produces: normalized JSON containing `project`, `repository`, `ref`, and `default_ref`; exits non-zero for invalid input.

- [ ] **Step 1: Write unit tests for the three fixed mappings, default refs, valid SHA/branch refs, rejected arbitrary projects, and unsafe refs.**

Run: `python3 scripts/test_private_ci_request.py`
Expected before implementation: import failure for `private_ci_request`.

- [ ] **Step 2: Implement `normalize_request(payload)` and a CLI that reads one JSON file and prints compact normalized JSON.**

- [ ] **Step 3: Run unit tests.**

Run: `python3 scripts/test_private_ci_request.py`
Expected: all tests pass.

- [ ] **Step 4: Commit.**

```bash
git add scripts/private_ci_request.py scripts/test_private_ci_request.py
git commit -m "feat(ci): validate private project requests"
```

### Task 2: Connector request workflow

**Files:**
- Create: `.github/workflows/request-private-project-ci.yml`
- Create: `triggers/private-ci.json`

**Interfaces:**
- Consumes: pushes to `build/private-ci` changing `triggers/private-ci.json`.
- Produces: a successful or failed no-secret workflow run named `Request private project CI`.

- [ ] **Step 1: Add a request workflow limited to the permanent branch and trigger file.**

The job checks out only the trigger JSON with `persist-credentials: false` and runs:

```bash
python3 scripts/private_ci_request.py request-source/triggers/private-ci.json
```

The trusted validator script is checked out from `main` into a separate directory before execution.

- [ ] **Step 2: Add a valid initial trigger for ZapZap's active branch.**

```json
{
  "project": "zapzap",
  "ref": "development/android-build-recovery"
}
```

- [ ] **Step 3: Commit.**

```bash
git add .github/workflows/request-private-project-ci.yml triggers/private-ci.json
git commit -m "feat(ci): add connector request bridge"
```

### Task 3: Privileged public CI workflow

**Files:**
- Create: `.github/workflows/run-private-project-ci.yml`

**Interfaces:**
- Consumes: `workflow_dispatch`, `repository_dispatch` type `private-project-ci`, or a successful trusted run of `Request private project CI`.
- Produces: one real project CI job and a public GitHub job summary; no uploaded artifacts.

- [ ] **Step 1: Add a normalization job that checks out trusted implementation from `main`, obtains the request from the matching event source, runs `private_ci_request.py`, and exposes project/repository/ref outputs.**

- [ ] **Step 2: Add the GoAnime job.**

Use Flutter 3.44.1 and run:

```bash
flutter pub get
pwsh ./tools/validate_project_health.ps1
dart format --output=none --set-exit-if-changed lib test packages tools
flutter analyze --no-pub
flutter test --no-pub
pwsh ./tools/validate_release_workflows.ps1
flutter build apk --debug --no-pub
```

- [ ] **Step 3: Add the ZapZap job.**

Use JDK 17, Android SDK 35, and run:

```bash
bash ./tools/checks/run_pure_tests.sh
bash ./tools/checks/audit_sources.sh
bash ./tools/checks/verify_android_baseline.sh
./gradlew --no-daemon testDebugUnitTest
./gradlew --no-daemon lintDebug
./gradlew --no-daemon :app:assembleDebug
```

- [ ] **Step 4: Add the SemogSite job.**

Use Node.js 22, activate the exact package manager from `package.json`, and run:

```bash
pnpm install --frozen-lockfile
pnpm check
pnpm build
```

- [ ] **Step 5: Add `always()` cleanup steps that remove the private checkout and write only project/ref/result metadata to the public job summary.**

- [ ] **Step 6: Commit.**

```bash
git add .github/workflows/run-private-project-ci.yml
git commit -m "feat(ci): run private project builds on public runners"
```

### Task 4: Static contract validator

**Files:**
- Create: `scripts/validate-private-ci-workflows.py`
- Create: `.github/workflows/validate-private-ci.yml`

**Interfaces:**
- Consumes: repository files from a normal public checkout.
- Produces: exit code 0 only when the request and privileged workflows preserve the documented allowlist and security invariants.

- [ ] **Step 1: Implement checks for fixed repositories/default refs, trusted workflow-run branch/actor/event checks, safe checkout flags, exact project commands, absence of `upload-artifact`, and absence of payload-provided commands or repository names.**

- [ ] **Step 2: Add a public validation workflow for relevant pushes and pull requests.**

Run:

```bash
python3 scripts/test_private_ci_request.py
python3 scripts/validate-private-ci-workflows.py
```

- [ ] **Step 3: Run both validators in a clean checkout.**

Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add scripts/validate-private-ci-workflows.py .github/workflows/validate-private-ci.yml
git commit -m "test(ci): enforce private CI hub contract"
```

### Task 5: Documentation and request branch

**Files:**
- Modify: `README.md`
- Create branch: `build/private-ci`

**Interfaces:**
- Documents: secret scope, manual/API/connector triggers, public-log warning, supported commands, and the absence of public build artifacts.
- Produces: a permanent connector request branch initialized from the final default-branch commit.

- [ ] **Step 1: Document the public CI hub, token configuration, supported projects/default refs, trigger examples, and security limitations.**

- [ ] **Step 2: Run the static validators after documentation changes.**

- [ ] **Step 3: Commit documentation.**

```bash
git add README.md
git commit -m "docs: explain public runner private CI hub"
```

- [ ] **Step 4: Merge the implementation branch after validation, then create `build/private-ci` from the merged default branch.**

- [ ] **Step 5: Change only `triggers/private-ci.json` on `build/private-ci` to request future connector-driven runs.**
