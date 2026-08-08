#!/usr/bin/env python3
"""Fail closed when private projects grow unreviewed source-local workflows."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "private-workflow-locality.json"
HUB_CONFIG = ROOT / "config" / "workflow-hub-projects.json"
API_ROOT = "https://api.github.com"
TOKEN_ENV = "PRIVATE_REPOSITORIES_TOKEN"
REPOSITORY_PATTERN = re.compile(r"^Semogtw/[A-Za-z0-9_.-]+$")
WORKFLOW_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+\.(?:yml|yaml)$")
AUTOMATIC_TRIGGER = re.compile(r"(?m)^  (?:push|pull_request|pull_request_target|schedule|repository_dispatch|workflow_run):")
MANUAL_TRIGGER = re.compile(r"(?m)^  workflow_dispatch:")


class AuditError(RuntimeError):
    pass


def api_json(path: str, token: str, *, allow_404: bool = False) -> Any | None:
    request = urllib.request.Request(
        f"{API_ROOT}{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Offline-Toolchains-private-workflow-audit/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if allow_404 and exc.code == 404:
            return None
        raise AuditError(f"GitHub API request failed with HTTP {exc.code}") from exc
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise AuditError("GitHub API request failed") from exc


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AuditError(f"cannot read {label}: {exc}") from exc
    if payload.get("schema_version") != 1:
        raise AuditError(f"{label} schema_version must be 1")
    projects = payload.get("projects")
    if not isinstance(projects, dict) or not projects:
        raise AuditError(f"{label} projects must be a non-empty object")
    return payload


def load_config() -> dict[str, Any]:
    return load_json(CONFIG, "locality config")


def validate_inventory_alignment(locality: dict[str, Any]) -> None:
    hub = load_json(HUB_CONFIG, "workflow hub inventory")
    private_hub = {
        key: value
        for key, value in hub["projects"].items()
        if isinstance(value, dict) and value.get("visibility") == "private"
    }
    locality_projects = locality["projects"]
    if set(private_hub) != set(locality_projects):
        missing = sorted(set(private_hub) - set(locality_projects))
        extra = sorted(set(locality_projects) - set(private_hub))
        raise AuditError(
            f"private project inventory drift; missing locality entries={missing}, extra={extra}"
        )

    for project, hub_entry in private_hub.items():
        locality_entry = locality_projects[project]
        if locality_entry.get("repository") != hub_entry.get("repository"):
            raise AuditError(f"{project}: repository differs between hub and locality inventories")
        if locality_entry.get("ref") != hub_entry.get("default_ref"):
            raise AuditError(f"{project}: ref differs between hub and locality inventories")
        hub_token = hub_entry.get("token_access")
        locality_token = locality_entry.get("token_access", "required")
        if hub_token == "verified" and locality_token != "required":
            raise AuditError(f"{project}: verified hub token must be required by locality audit")
        if hub_token == "pending-secret-scope" and locality_token != "pending":
            raise AuditError(f"{project}: pending hub token scope must be pending in locality audit")
        if hub_token not in {"verified", "pending-secret-scope"}:
            raise AuditError(f"{project}: private hub project must declare token_access state")


def normalized_project(
    project: str, data: Any
) -> tuple[str, str, str, dict[str, dict[str, str]]]:
    if not isinstance(data, dict):
        raise AuditError(f"invalid project entry: {project}")
    repository = data.get("repository")
    ref = data.get("ref")
    token_access = data.get("token_access", "required")
    allowed = data.get("allowed_source_local_workflows")
    if not isinstance(repository, str) or not REPOSITORY_PATTERN.fullmatch(repository):
        raise AuditError(f"invalid fixed repository mapping for {project}")
    if not isinstance(ref, str) or not ref or any(char.isspace() for char in ref):
        raise AuditError(f"invalid ref for {project}")
    if token_access not in {"required", "pending"}:
        raise AuditError(f"invalid token_access for {project}")
    if not isinstance(allowed, dict):
        raise AuditError(f"invalid workflow allowlist for {project}")

    normalized: dict[str, dict[str, str]] = {}
    for filename, metadata in allowed.items():
        if not isinstance(filename, str) or not WORKFLOW_PATTERN.fullmatch(filename):
            raise AuditError(f"invalid workflow filename in {project}")
        if not isinstance(metadata, dict):
            raise AuditError(f"invalid metadata for {project}/{filename}")
        kind = metadata.get("kind")
        reason = metadata.get("reason")
        if kind not in {"privileged", "manual-marker"}:
            raise AuditError(f"invalid workflow kind for {project}/{filename}")
        if not isinstance(reason, str) or not reason.strip():
            raise AuditError(f"missing workflow reason for {project}/{filename}")
        normalized[filename] = {"kind": kind, "reason": reason.strip()}
    return repository, ref, token_access, normalized


def repository_accessible(repository: str, token: str) -> bool:
    owner, repo = repository.split("/", 1)
    return api_json(f"/repos/{owner}/{repo}", token, allow_404=True) is not None


def workflow_names(repository: str, ref: str, token: str) -> set[str]:
    owner, repo = repository.split("/", 1)
    encoded_ref = urllib.parse.quote(ref, safe="")
    listing = api_json(
        f"/repos/{owner}/{repo}/contents/.github/workflows?ref={encoded_ref}",
        token,
        allow_404=True,
    )
    if listing is None:
        return set()
    if not isinstance(listing, list):
        raise AuditError(f"unexpected workflows response for {repository}")

    names: set[str] = set()
    for item in listing:
        if not isinstance(item, dict) or item.get("type") != "file":
            continue
        name = item.get("name")
        if isinstance(name, str) and WORKFLOW_PATTERN.fullmatch(name):
            names.add(name)
    return names


def workflow_text(repository: str, ref: str, filename: str, token: str) -> str:
    owner, repo = repository.split("/", 1)
    encoded_ref = urllib.parse.quote(ref, safe="")
    encoded_path = urllib.parse.quote(f".github/workflows/{filename}", safe="/")
    payload = api_json(
        f"/repos/{owner}/{repo}/contents/{encoded_path}?ref={encoded_ref}", token
    )
    if not isinstance(payload, dict) or payload.get("encoding") != "base64":
        raise AuditError(f"cannot inspect manual marker in {repository}")
    encoded = payload.get("content")
    if not isinstance(encoded, str):
        raise AuditError(f"invalid manual marker payload in {repository}")
    try:
        return base64.b64decode(encoded, validate=False).decode("utf-8")
    except (ValueError, UnicodeDecodeError) as exc:
        raise AuditError(f"invalid UTF-8 workflow marker in {repository}") from exc


def fingerprint_names(names: set[str]) -> list[str]:
    return sorted(hashlib.sha256(name.encode("utf-8")).hexdigest()[:12] for name in names)


def audit() -> None:
    token = os.environ.get(TOKEN_ENV, "").strip()
    if not token:
        raise AuditError(f"missing {TOKEN_ENV}")

    payload = load_config()
    validate_inventory_alignment(payload)
    pending_access: list[str] = []

    for project, raw in payload["projects"].items():
        repository, ref, token_access, allowed = normalized_project(project, raw)
        accessible = repository_accessible(repository, token)
        if not accessible:
            if token_access == "pending":
                pending_access.append(project)
                print(f"{project}: PENDING TOKEN SCOPE (workflow locality not yet auditable)")
                continue
            raise AuditError(f"{project}: read-only token cannot access reviewed repository")
        if token_access == "pending":
            raise AuditError(
                f"{project}: token access now works; change token_access from pending to required"
            )

        actual = workflow_names(repository, ref, token)
        expected = set(allowed)
        unexpected = actual - expected
        missing = expected - actual
        if unexpected or missing:
            details = []
            if unexpected:
                details.append(
                    "unexpected workflow-name hashes=" + ",".join(fingerprint_names(unexpected))
                )
            if missing:
                details.append("missing reviewed workflows=" + ",".join(sorted(missing)))
            raise AuditError(f"{project}: workflow locality drift ({'; '.join(details)})")

        for filename, metadata in allowed.items():
            if metadata["kind"] != "manual-marker":
                continue
            text = workflow_text(repository, ref, filename, token)
            if not MANUAL_TRIGGER.search(text):
                raise AuditError(f"{project}: manual marker {filename} lost workflow_dispatch")
            if AUTOMATIC_TRIGGER.search(text):
                raise AuditError(f"{project}: manual marker {filename} regained an automatic trigger")
            if "secrets." in text or "PRIVATE_REPOSITORIES_TOKEN" in text:
                raise AuditError(f"{project}: manual marker {filename} must not receive secrets")

        print(f"{project}: PASS ({len(actual)} reviewed source-local workflow(s))")

    if pending_access:
        print(
            "private workflow locality audit: PASS WITH PENDING TOKEN SCOPE: "
            + ", ".join(sorted(pending_access))
        )
    else:
        print("private workflow locality audit: PASS")


def main() -> int:
    try:
        audit()
    except AuditError as exc:
        print(f"private workflow locality audit: FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
