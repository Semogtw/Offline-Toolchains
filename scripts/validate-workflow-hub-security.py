#!/usr/bin/env python3
"""Static security policy for the public workflow hub."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
INVENTORY = ROOT / "config" / "workflow-hub-projects.json"
POLICY_DOC = ROOT / "docs" / "WORKFLOW_HUB_SECURITY.md"

PRIVATE_TOKEN = "PRIVATE_REPOSITORIES_TOKEN"
UPLOAD = "uses: actions/upload-artifact@"
SENSITIVE_EXTENSIONS = (
    ".apk",
    ".aab",
    ".jks",
    ".keystore",
    ".p12",
    ".pfx",
    ".pem",
    ".key",
    ".env",
    ".db",
    ".sqlite",
    ".sqlite3",
)


class PolicyError(RuntimeError):
    pass


def _load_inventory() -> dict:
    try:
        payload = json.loads(INVENTORY.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PolicyError(f"cannot load workflow inventory: {exc}") from exc

    if payload.get("schema_version") != 1:
        raise PolicyError("workflow inventory schema_version must be 1")
    policy = payload.get("policy", {})
    if policy.get("sensitive_artifact_retention_days") != 1:
        raise PolicyError("workflow inventory must pin sensitive artifact retention to one day")
    public_max = policy.get("public_artifact_max_retention_days")
    if not isinstance(public_max, int) or not 1 <= public_max <= 7:
        raise PolicyError("public artifact maximum retention must be between one and seven days")

    projects = payload.get("projects")
    if not isinstance(projects, dict):
        raise PolicyError("workflow inventory projects must be an object")

    expected = {"goanime", "zapzap", "semogsite", "hydra", "receitas", "fichario"}
    missing = sorted(expected - set(projects))
    if missing:
        raise PolicyError(f"workflow inventory is missing active projects: {missing}")

    repositories: list[str] = []
    for key, project in projects.items():
        if not isinstance(project, dict):
            raise PolicyError(f"invalid project entry: {key}")
        repository = project.get("repository")
        if not isinstance(repository, str) or not re.fullmatch(
            r"Semogtw/[A-Za-z0-9_.-]+", repository
        ):
            raise PolicyError(f"invalid fixed repository for {key}")
        repositories.append(repository)
        if project.get("visibility") not in {"private", "public"}:
            raise PolicyError(f"invalid visibility for {key}")
        if project.get("source_export") == "encrypted" and project.get("visibility") != "private":
            raise PolicyError(f"encrypted private-source export assigned to public project {key}")

    if len(repositories) != len(set(repositories)):
        raise PolicyError("workflow inventory contains duplicate repositories")
    return payload


def _step_blocks(text: str) -> list[str]:
    starts = [m.start() for m in re.finditer(r"(?m)^      - (?:name:|uses:)", text)]
    if not starts:
        return []
    starts.append(len(text))
    return [text[starts[i] : starts[i + 1]] for i in range(len(starts) - 1)]


def _validate_uploads(path: Path, text: str, public_max_days: int) -> None:
    for step in _step_blocks(text):
        if UPLOAD not in step:
            continue

        retention = re.search(r"(?m)^\s+retention-days:\s*(\d+)\s*$", step)
        if retention is None:
            raise PolicyError(f"{path.name}: uploaded artifacts must declare retention-days")
        retention_days = int(retention.group(1))
        if not 1 <= retention_days <= public_max_days:
            raise PolicyError(
                f"{path.name}: artifact retention must be 1-{public_max_days} days"
            )

        lowered = step.lower()
        encrypted_transfer = ".gpg" in lowered or "encrypted" in lowered or "transfer" in lowered
        sensitive_upload = PRIVATE_TOKEN in text and (
            encrypted_transfer
            or "apk" in lowered
            or "private-source" in lowered
            or any(ext in lowered for ext in SENSITIVE_EXTENSIONS)
        )
        if sensitive_upload and retention_days != 1:
            raise PolicyError(
                f"{path.name}: sensitive/private artifact transfer must use retention-days: 1"
            )

        if PRIVATE_TOKEN in text:
            if any(ext in lowered for ext in SENSITIVE_EXTENSIONS) and not encrypted_transfer:
                raise PolicyError(
                    f"{path.name}: private-token workflow appears to upload a raw sensitive file"
                )
            if "apk" in lowered and not encrypted_transfer:
                raise PolicyError(
                    f"{path.name}: private APK artifact must be encrypted before upload"
                )
            if ("diagnostic" in lowered or "gate-log" in lowered or ".log" in lowered) and not encrypted_transfer:
                raise PolicyError(
                    f"{path.name}: private-source diagnostic logs must not be uploaded in plaintext"
                )


def _validate_private_token_workflow(path: Path, text: str) -> None:
    if PRIVATE_TOKEN not in text:
        return

    forbidden = {
        "pull_request_target:": "must not expose private credentials to pull_request_target",
        "persist-credentials: true": "must not persist checkout credentials",
        "secrets: inherit": "must not inherit arbitrary secrets",
        "permissions: write-all": "must not request write-all permissions",
        "set -x": "must not enable shell xtrace in a private-token workflow",
    }
    for needle, reason in forbidden.items():
        if needle in text:
            raise PolicyError(f"{path.name}: {reason}")

    if "permissions:" not in text or "contents: read" not in text:
        raise PolicyError(f"{path.name}: private-token workflow must explicitly include contents: read")

    for step in _step_blocks(text):
        if "uses: actions/setup-node@" in step and re.search(r"(?m)^\s+cache:", step):
            raise PolicyError(f"{path.name}: setup-node cache is forbidden for private checkouts")
        if "uses: gradle/actions/setup-gradle@" in step and "cache-disabled: true" not in step:
            raise PolicyError(f"{path.name}: Gradle setup must disable shared cache for private CI")


def validate() -> None:
    inventory = _load_inventory()
    if not POLICY_DOC.is_file():
        raise PolicyError("missing workflow hub security policy document")
    if not WORKFLOWS.is_dir():
        raise PolicyError("missing .github/workflows directory")

    workflow_paths = sorted((*WORKFLOWS.glob("*.yml"), *WORKFLOWS.glob("*.yaml")))
    if not workflow_paths:
        raise PolicyError("no workflow files found")

    public_max_days = inventory["policy"]["public_artifact_max_retention_days"]
    for path in workflow_paths:
        text = path.read_text(encoding="utf-8")
        _validate_uploads(path, text, public_max_days)
        _validate_private_token_workflow(path, text)


def main() -> int:
    try:
        validate()
    except PolicyError as exc:
        print(f"workflow hub security: FAIL: {exc}", file=sys.stderr)
        return 1
    print("workflow hub security: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
