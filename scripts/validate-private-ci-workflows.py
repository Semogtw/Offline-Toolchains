#!/usr/bin/env python3
"""Enforce the security and execution contract of the public CI hub."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_WORKFLOW = ROOT / ".github/workflows/run-private-project-ci.yml"
FICHARIO_WORKFLOW = ROOT / ".github/workflows/run-fichario-ci.yml"
REQUEST_WORKFLOW = ROOT / ".github/workflows/request-private-project-ci.yml"
REPORT_WORKFLOW = ROOT / ".github/workflows/report-private-project-ci-runs.yml"
REQUEST_FILE = ROOT / "triggers/private-ci.json"
REQUEST_LIBRARY = ROOT / "scripts/private_ci_request.py"
DESIGN = ROOT / "docs/superpowers/specs/2026-08-01-public-private-ci-hub-design.md"
PLAN = ROOT / "docs/superpowers/plans/2026-08-01-public-private-ci-hub.md"
OPERATIONS = ROOT / "docs/private-project-ci.md"

EXPECTED_PROJECTS = {
    "goanime": {
        "repository": "Semogtw/goanime-mobile",
        "default_ref": "main",
    },
    "zapzap": {
        "repository": "Semogtw/Zapzap",
        "default_ref": "development/android-build-recovery",
    },
    "semogsite": {
        "repository": "Semogtw/SemogSite",
        "default_ref": "develop/foundation-bootstrap",
    },
    "fichario": {
        "repository": "Semogtw/FicharioVirtual",
        "default_ref": "main",
    },
}


class ContractError(RuntimeError):
    """Raised when a checked repository file violates the CI contract."""


def read(path: Path) -> str:
    if not path.is_file():
        raise ContractError(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def require(text: str, fragment: str, context: str) -> None:
    if fragment not in text:
        raise ContractError(f"{context}: missing required fragment: {fragment!r}")


def require_count(text: str, fragment: str, count: int, context: str) -> None:
    actual = text.count(fragment)
    if actual != count:
        raise ContractError(
            f"{context}: expected {count} occurrences of {fragment!r}, found {actual}"
        )


def forbid(text: str, fragment: str, context: str) -> None:
    if fragment in text:
        raise ContractError(f"{context}: forbidden fragment present: {fragment!r}")


def validate_request_library(text: str) -> None:
    for project, config in EXPECTED_PROJECTS.items():
        require(text, f'"{project}": {{', "request library")
        require(text, f'"repository": "{config["repository"]}"', "request library")
        require(text, f'"default_ref": "{config["default_ref"]}"', "request library")

    for safety_check in (
        '".." in ref',
        '"@{" in ref',
        '"//" in ref',
        'ref.endswith(".lock")',
        "unknown_keys = set(payload) - _ALLOWED_KEYS",
    ):
        require(text, safety_check, "request library")


def validate_request_workflow(text: str) -> None:
    for fragment in (
        "name: Request private project CI",
        "- build/private-ci",
        "- triggers/private-ci.json",
        'test "$ACTOR" = "$OWNER"',
        "ref: main",
        "path: trusted-source",
        "persist-credentials: false",
        "sparse-checkout: scripts/private_ci_request.py",
        "ref: ${{ github.sha }}",
        "sparse-checkout: triggers/private-ci.json",
        "python3 trusted-source/scripts/private_ci_request.py",
    ):
        require(text, fragment, "request workflow")

    for fragment in (
        "secrets.",
        "PRIVATE_REPOSITORIES_TOKEN",
        "actions/upload-artifact",
        "repository:",
        "client_payload",
    ):
        forbid(text, fragment, "request workflow")


def validate_privileged_workflow(text: str) -> None:
    for fragment in (
        "name: Run private project CI",
        "workflow_dispatch:",
        "repository_dispatch:",
        "- private-project-ci",
        "workflow_run:",
        "- Request private project CI",
        "github.event.workflow_run.conclusion == 'success'",
        "github.event.workflow_run.head_branch == 'build/private-ci'",
        "github.event.workflow_run.event == 'push'",
        "github.event.workflow_run.actor.login == github.repository_owner",
        "github.event.workflow_run.head_repository.full_name == github.repository",
        'test "$ACTOR" = "$OWNER"',
        "ref: main",
        "python3 trusted-source/scripts/private_ci_request.py",
        "PRIVATE_REPOSITORIES_TOKEN",
        "repository: ${{ needs.normalize.outputs.repository }}",
        "ref: ${{ needs.normalize.outputs.ref }}",
        "flutter pub get",
        "run: ./tools/validate_project_health.ps1",
        "dart format --output=none --set-exit-if-changed lib test packages tools",
        "flutter analyze --no-pub",
        "flutter test --no-pub",
        "run: ./tools/validate_release_workflows.ps1",
        "flutter build apk --debug --no-pub",
        "bash ./tools/checks/run_pure_tests.sh",
        "bash ./tools/checks/audit_sources.sh",
        "bash ./tools/checks/verify_android_baseline.sh",
        "./gradlew --no-daemon testDebugUnitTest",
        "./gradlew --no-daemon lintDebug",
        "./gradlew --no-daemon :app:assembleDebug",
        "pnpm install --frozen-lockfile",
        "pnpm check",
        "pnpm build",
        'corepack prepare "$package_manager" --activate',
    ):
        require(text, fragment, "privileged workflow")

    require_count(text, "path: private-source", 3, "privileged workflow")
    require_count(text, "fetch-depth: 1", 3, "privileged workflow")
    require_count(text, "persist-credentials: false", 5, "privileged workflow")
    require_count(text, "lfs: false", 3, "privileged workflow")
    require_count(text, "submodules: false", 3, "privileged workflow")
    require_count(text, "shell: pwsh", 2, "privileged workflow")
    require_count(
        text,
        'run: rm -rf "$GITHUB_WORKSPACE/private-source"',
        3,
        "privileged workflow",
    )
    require_count(
        text,
        "Build outputs were verified and discarded; no private artifact was uploaded.",
        3,
        "privileged workflow",
    )

    for fragment in (
        "actions/upload-artifact",
        "actions/cache",
        "cache: true",
        "client_payload.repository",
        "client_payload.command",
        "client_payload.script",
        "client_payload.runner",
        "secrets: inherit",
        "persist-credentials: true",
        "FicharioVirtual",
        "fichario",
    ):
        forbid(text, fragment, "privileged workflow")


def validate_fichario_workflow(text: str) -> None:
    for fragment in (
        "name: Run Fichario CI",
        "workflow_dispatch:",
        "workflow_run:",
        "- Request private project CI",
        "github.event.workflow_run.conclusion == 'success'",
        "github.event.workflow_run.head_branch == 'build/private-ci'",
        "github.event.workflow_run.event == 'push'",
        "github.event.workflow_run.actor.login == github.repository_owner",
        "github.event.workflow_run.head_repository.full_name == github.repository",
        "python3 trusted-source/scripts/private_ci_request.py",
        'test "$PROJECT" = "fichario"',
        "repository: Semogtw/FicharioVirtual",
        "ref: ${{ steps.request.outputs.ref }}",
        "path: public-source",
        "persist-credentials: false",
        "fetch-depth: 1",
        "uses: pnpm/action-setup@v6",
        "version: 10",
        "uses: actions/setup-node@v6",
        'node-version: "22.16.0"',
        "pnpm install --frozen-lockfile",
        "pnpm exec playwright install --with-deps chromium",
        "uses: denoland/setup-deno@v2",
        "uses: supabase/setup-cli@v1",
        "run: pnpm verify:full",
        'run: rm -rf "$GITHUB_WORKSPACE/public-source"',
        "Fichário Virtual complete verification",
    ):
        require(text, fragment, "Fichario workflow")

    for fragment in (
        "PRIVATE_REPOSITORIES_TOKEN",
        "secrets.",
        "actions/upload-artifact",
        "actions/cache",
        "cache: true",
        "persist-credentials: true",
        "client_payload.repository",
        "client_payload.command",
        "secrets: inherit",
    ):
        forbid(text, fragment, "Fichario workflow")


def validate_report_workflow(text: str) -> None:
    for fragment in (
        "name: Report private project CI runs",
        "- Run private project CI",
        "- Run Fichario CI",
        "actions: read",
        "issues: write",
        "github.event.workflow_run.head_repository.full_name == github.repository",
        "github.event.workflow_run.actor.login == github.repository_owner",
        "uses: actions/github-script@v8",
        "github.rest.actions.listJobsForWorkflowRun",
        "GoAnime real CI and Android debug build",
        "ZapZap real Android CI and debug build",
        "SemogSite real checks and production build",
        "Fichário Virtual complete verification",
        "issue_number: 15",
        "Private source, private resolved commit, logs, artifacts, and build outputs are intentionally omitted.",
    ):
        require(text, fragment, "receipt workflow")

    for fragment in (
        "PRIVATE_REPOSITORIES_TOKEN",
        "secrets.",
        "contents: write",
        "actions/upload-artifact",
        "actions/cache",
        "downloadJobLogsForWorkflowRun",
        "downloadWorkflowRunLogs",
        "client_payload",
    ):
        forbid(text, fragment, "receipt workflow")


def validate_request_json() -> None:
    try:
        payload = json.loads(read(REQUEST_FILE))
    except json.JSONDecodeError as exc:
        raise ContractError(
            f"trigger request is invalid JSON at line {exc.lineno}, column {exc.colno}"
        ) from exc

    sys.path.insert(0, str((ROOT / "scripts").resolve()))
    from private_ci_request import normalize_request

    normalized = normalize_request(payload)
    if normalized["project"] not in EXPECTED_PROJECTS:
        raise ContractError("trigger request normalized to an unsupported project")


def validate_docs() -> None:
    design = read(DESIGN)
    plan = read(PLAN)
    operations = read(OPERATIONS)
    for project, config in EXPECTED_PROJECTS.items():
        require(design, f"`{project}`", "design")
        require(design, f"`{config['repository']}`", "design")
        require(plan, config["repository"], "plan")
    require(operations, "Public private CI run receipts", "operations")
    require(operations, "issue #15", "operations")
    require(operations, "fichario", "operations")
    forbid(design, "TBD", "design")
    forbid(plan, "TBD", "plan")


def main() -> int:
    try:
        validate_request_library(read(REQUEST_LIBRARY))
        validate_request_workflow(read(REQUEST_WORKFLOW))
        validate_privileged_workflow(read(RUN_WORKFLOW))
        validate_fichario_workflow(read(FICHARIO_WORKFLOW))
        validate_report_workflow(read(REPORT_WORKFLOW))
        validate_request_json()
        validate_docs()
    except (ContractError, ValueError) as exc:
        print(f"private CI workflow contract: FAIL: {exc}", file=sys.stderr)
        return 1

    print("private CI workflow contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
