# GoAnime Deterministic Offline Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a relocatable GoAnime Flutter toolchain whose Pub cache exactly covers the sanitized hosted entries from the private lock.

**Architecture:** Keep private lock parsing local and publish only a validated package/version manifest. Hydrate an exact synthetic project in GitHub Actions, repair Flutter's absolute package metadata at activation time, and validate with download endpoints disabled.

**Tech Stack:** Python 3 standard library, Bash, Flutter 3.44.1, Dart 3.12.1, GitHub Actions.

## Global Constraints

- Never publish private source, URLs, paths, Git dependencies, refs, commit IDs, tokens, or signing data.
- Artifact parts remain at 400 MiB with one-day retention.
- Validation must work without network after the artifact has been assembled.

---

### Task 1: Sanitized hosted lock helper

**Files:**
- Create: `scripts/goanime_lock_cache.py`
- Create: `scripts/test_goanime_lock_cache.py`
- Create: `fixtures/goanime/hosted-lock.json`

- [x] Write failing tests for hosted-only extraction, exact pubspec generation, and missing-cache diagnostics.
- [x] Implement the standard-library helper.
- [x] Generate the 148-package sanitized manifest from the current GoAnime lock.
- [x] Run `python3 -m unittest scripts/test_goanime_lock_cache.py`.

### Task 2: Portable Flutter repair

**Files:**
- Create: `scripts/repair-portable-flutter.sh`
- Create: `scripts/test_repair_portable_flutter.sh`

- [x] Write a failing relocation test with a fake bundled Dart executable.
- [x] Implement path-stamped offline regeneration of `flutter_tools/.dart_tool`.
- [x] Run `bash scripts/test_repair_portable_flutter.sh`.

### Task 3: Workflow integration

**Files:**
- Modify: `.github/workflows/build-goanime.yml`
- Create: `scripts/validate-goanime-toolchain.sh`

- [x] Hydrate the exact hosted dependency fixture before the broad build fixture.
- [x] Include repair and verification helpers in the portable archive.
- [x] Validate the relocated bundle with download endpoints disabled.
- [x] Keep the existing 400 MiB split artifacts and one-day retention.

### Task 4: End-to-end validation

- [ ] Run the pull-request workflow.
- [ ] Download and verify the new artifact hashes.
- [ ] Extract the bundle beside the current private source bundle.
- [ ] Run locked Pub resolution, formatter, analyzer, Flutter tests, Node tests, shell contracts, and project health checks.
