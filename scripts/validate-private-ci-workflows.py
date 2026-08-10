#!/usr/bin/env python3
"""Enforce the live security/execution contract of the public CI hub."""

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
RECEITAS_REQUEST_WORKFLOW = ROOT / ".github/workflows/request-receitas-ci.yml"
RECEITAS_RUN_WORKFLOW = ROOT / ".github/workflows/run-receitas-ci.yml"
RECEITAS_REQUEST_FILE = ROOT / "triggers/receitas-ci.json"
INVENTORY = ROOT / "config/workflow-hub-projects.json"
OPERATIONS = ROOT / "docs/private-project-ci.md"
SECURITY = ROOT / "docs/WORKFLOW_HUB_SECURITY.md"

EXPECTED_PROJECTS = {
    "goanime": ("Semogtw/goanime-mobile", "main"),
    "zapzap": ("Semogtw/Zapzap", "development/android-build-recovery"),
    "semogsite": ("Semogtw/SemogSite", "main"),
    "hydra": ("Semogtw/HydraPersonalizado", "main"),
    "receitas": ("Semogtw/Receitas", "main"),
    "fichario": ("Semogtw/FicharioVirtual", "main"),
}


class ContractError(RuntimeError):
    pass


def read(path: Path) -> str:
    if not path.is_file():
        raise ContractError(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def require(text: str, fragment: str, context: str) -> None:
    if fragment not in text:
        raise ContractError(f"{context}: missing required fragment: {fragment!r}")


def forbid(text: str, fragment: str, context: str) -> None:
    if fragment in text:
        raise ContractError(f"{context}: forbidden fragment present: {fragment!r}")


def validate_mappings() -> None:
    sys.path.insert(0, str((ROOT / "scripts").resolve()))
    from private_ci_request import PROJECTS, normalize_request

    if set(PROJECTS) != set(EXPECTED_PROJECTS):
        raise ContractError(
            f"request allowlist mismatch: expected {sorted(EXPECTED_PROJECTS)}, got {sorted(PROJECTS)}"
        )

    inventory = json.loads(read(INVENTORY))
    for project, (repository, default_ref) in EXPECTED_PROJECTS.items():
        normalized = normalize_request({"project": project})
        if normalized["repository"] != repository or normalized["ref"] != default_ref:
            raise ContractError(f"unsafe or stale mapping for {project}")
        entry = inventory["projects"][project]
        if entry["repository"] != repository or entry["default_ref"] != default_ref:
            raise ContractError(f"inventory mapping mismatch for {project}")
        if project == "fichario":
            expected_ci = "run-fichario-ci"
        elif project == "receitas":
            expected_ci = "run-receitas-ci"
        else:
            expected_ci = "run-private-project-ci"
        if entry["central_ci"] != expected_ci:
            raise ContractError(f"central_ci mismatch for {project}")

    payload = json.loads(read(REQUEST_FILE))
    if normalize_request(payload)["project"] not in EXPECTED_PROJECTS:
        raise ContractError("trigger request normalized to an unsupported project")

    receitas_payload = json.loads(read(RECEITAS_REQUEST_FILE))
    if set(receitas_payload) != {"ref"} or not isinstance(receitas_payload["ref"], str) or not receitas_payload["ref"]:
        raise ContractError("Receitas trigger must contain exactly one non-empty ref")


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
        "python3 trusted-source/scripts/private_ci_request.py",
    ):
        require(text, fragment, "request workflow")
    for fragment in ("secrets.", "PRIVATE_REPOSITORIES_TOKEN", "actions/upload-artifact", "client_payload"):
        forbid(text, fragment, "request workflow")


def validate_receitas_request_workflow(text: str) -> None:
    for fragment in (
        "name: Request Receitas CI",
        "- build/receitas-ci",
        "- triggers/receitas-ci.json",
        'test "$ACTOR" = "$OWNER"',
        "persist-credentials: false",
        "sparse-checkout: triggers/receitas-ci.json",
        "request must contain exactly the ref field",
        "unsafe git ref",
    ):
        require(text, fragment, "Receitas request workflow")
    for fragment in (
        "secrets.",
        "PRIVATE_REPOSITORIES_TOKEN",
        "actions/upload-artifact",
        "repository:",
        "client_payload",
        "set -x",
    ):
        forbid(text, fragment, "Receitas request workflow")


def validate_privileged_workflow(text: str) -> None:
    for fragment in (
        "name: Run private project CI",
        "workflow_dispatch:",
        "repository_dispatch:",
        "workflow_run:",
        "github.event.workflow_run.actor.login == github.repository_owner",
        "github.event.workflow_run.head_repository.full_name == github.repository",
        "PRIVATE_REPOSITORIES_TOKEN",
        "repository: ${{ needs.normalize.outputs.repository }}",
        "persist-credentials: false",
        "GoAnime real CI and Android debug build",
        "ZapZap real Android CI and debug build",
        "SemogSite full checks and production build",
        "Hydra real repository gates",
        "Receitas repository and documentation guards",
        "pnpm check:public-confidentiality",
        "playwright test tests/e2e/workflow-orchestration.spec.ts",
        "yarn typecheck:node",
        "yarn format-check",
        "Receitas executable stack detected; promote its public-runner CI profile",
        "Private repository/ref details are intentionally omitted from the public summary.",
    ):
        require(text, fragment, "privileged workflow")
    for project in ("goanime", "zapzap", "semogsite", "hydra", "receitas"):
        require(text, f"- {project}", "workflow_dispatch choices")
    for fragment in (
        "actions/upload-artifact",
        "actions/cache",
        "persist-credentials: true",
        "secrets: inherit",
        "client_payload.repository",
        "client_payload.command",
        "set -x",
    ):
        forbid(text, fragment, "privileged workflow")


def validate_receitas_run_workflow(text: str) -> None:
    for fragment in (
        "name: Run Receitas CI",
        "workflow_run:",
        "Request Receitas CI",
        "github.event.workflow_run.actor.login == github.repository_owner",
        "github.event.workflow_run.head_repository.full_name == github.repository",
        "PRIVATE_REPOSITORIES_TOKEN",
        "repository: Semogtw/Receitas",
        "ref: ${{ steps.request.outputs.ref }}",
        "persist-credentials: false",
        "fetch-depth: 1",
        "lfs: false",
        "submodules: false",
        "node-version: '24.18.0'",
        "pnpm install --frozen-lockfile",
        "pnpm install --no-frozen-lockfile",
        "pnpm test:release-scripts",
        "pnpm verify:source",
        "pnpm lint",
        "pnpm typecheck",
        "pnpm test:run",
        "pnpm build:pages",
        "reproducible lockfile",
        "rm -rf \"$GITHUB_WORKSPACE/private-source\"",
        "no artifact was uploaded",
    ):
        require(text, fragment, "Receitas run workflow")
    for fragment in (
        "actions/upload-artifact",
        "actions/cache",
        "persist-credentials: true",
        "secrets: inherit",
        "pull_request_target",
        "set -x",
        "E2E_PASSWORD",
        "SUPABASE_SERVICE_ROLE_KEY",
    ):
        forbid(text, fragment, "Receitas run workflow")


def validate_fichario_workflow(text: str) -> None:
    for fragment in (
        "name: Run Fichario CI",
        "needs.normalize.outputs.project == 'fichario'",
        "repository: Semogtw/FicharioVirtual",
        "persist-credentials: false",
        "run: pnpm verify:full",
        "Fichário Virtual complete verification",
    ):
        require(text, fragment, "Fichario workflow")
    for fragment in ("PRIVATE_REPOSITORIES_TOKEN", "secrets.", "actions/upload-artifact", "persist-credentials: true"):
        forbid(text, fragment, "Fichario workflow")


def validate_report(text: str) -> None:
    for name in (
        "GoAnime real CI and Android debug build",
        "ZapZap real Android CI and debug build",
        "SemogSite full checks and production build",
        "Hydra real repository gates",
        "Receitas repository and documentation guards",
        "Fichário Virtual complete verification",
    ):
        require(text, name, "receipt workflow")
    for fragment in ("PRIVATE_REPOSITORIES_TOKEN", "secrets.", "downloadWorkflowRunLogs", "downloadJobLogsForWorkflowRun"):
        forbid(text, fragment, "receipt workflow")


def validate_docs() -> None:
    operations = read(OPERATIONS)
    security = read(SECURITY)
    for project, (repository, _) in EXPECTED_PROJECTS.items():
        require(operations, f"`{project}`", "operations")
        require(operations, f"`{repository}`", "operations")
    require(operations, "issue #15", "operations")
    require(operations, "retention", "operations")
    require(operations, "Run Receitas CI", "operations")
    require(security, "ciphertext-only", "security policy")
    require(security, "Receitas", "security policy")


def main() -> int:
    try:
        validate_mappings()
        validate_request_workflow(read(REQUEST_WORKFLOW))
        validate_receitas_request_workflow(read(RECEITAS_REQUEST_WORKFLOW))
        validate_privileged_workflow(read(RUN_WORKFLOW))
        validate_receitas_run_workflow(read(RECEITAS_RUN_WORKFLOW))
        validate_fichario_workflow(read(FICHARIO_WORKFLOW))
        validate_report(read(REPORT_WORKFLOW))
        validate_docs()
    except (ContractError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"private CI workflow contract: FAIL: {exc}", file=sys.stderr)
        return 1
    print("private CI workflow contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
