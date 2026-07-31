#!/usr/bin/env python3
"""Schema-v2 artifact contract helpers using only the Python standard library."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

SCHEMA_VERSION = 2
SUPPORTED_PLATFORM = "linux"
SUPPORTED_ARCHITECTURE = "x86_64"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,99}$")
ARTIFACT_SET_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,199}$")
REQUIRED_MANIFEST_KEYS = {
    "schema_version",
    "artifact_set_id",
    "set_fingerprint",
    "profile",
    "package",
    "lock_mode",
    "lock_fingerprint",
    "builder_fingerprint",
    "workflow",
    "workflow_commit",
    "run_id",
    "created_at",
    "expires_at",
    "platform",
    "architecture",
    "archive",
    "parts",
    "requires",
    "activation_script",
    "doctor_script",
    "software_inventory",
    "compatibility",
}


def canonical_json_bytes(document: Any) -> bytes:
    return json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def compute_fingerprint(parts: Iterable[bytes]) -> str:
    digest = hashlib.sha256()
    for part in parts:
        digest.update(len(part).to_bytes(8, "big"))
        digest.update(part)
    return digest.hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_relative_path(value: str, *, allow_empty: bool = False) -> bool:
    if not isinstance(value, str) or (not value and not allow_empty):
        return False
    if "\\" in value or "\x00" in value:
        return False
    path = PurePosixPath(value)
    if path.is_absolute():
        return False
    return all(part not in {"", ".", ".."} for part in path.parts)


def _validate_name(value: Any, field: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not NAME_RE.fullmatch(value):
        errors.append(f"{field} must match {NAME_RE.pattern}")


def _validate_sha(value: Any, field: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        errors.append(f"{field} must be a lowercase SHA-256")


def validate_manifest(document: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["manifest must be an object"]

    missing = sorted(REQUIRED_MANIFEST_KEYS - set(document))
    if missing:
        errors.append(f"missing keys: {missing}")

    if document.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}")
    _validate_name(document.get("profile"), "profile", errors)
    _validate_sha(document.get("set_fingerprint"), "set_fingerprint", errors)
    _validate_name(document.get("package"), "package", errors)
    artifact_set_id = document.get("artifact_set_id")
    if not isinstance(artifact_set_id, str) or not ARTIFACT_SET_RE.fullmatch(artifact_set_id):
        errors.append("artifact_set_id has an invalid shape")

    if document.get("lock_mode") not in {"synthetic", "private-exact", "not-applicable"}:
        errors.append("lock_mode is unsupported")
    _validate_sha(document.get("lock_fingerprint"), "lock_fingerprint", errors)
    _validate_sha(document.get("builder_fingerprint"), "builder_fingerprint", errors)
    workflow_commit = document.get("workflow_commit")
    if not isinstance(workflow_commit, str) or not GIT_SHA_RE.fullmatch(workflow_commit):
        errors.append("workflow_commit must be a lowercase 40-character Git SHA")

    if document.get("platform") != SUPPORTED_PLATFORM:
        errors.append(f"platform must be {SUPPORTED_PLATFORM}")
    if document.get("architecture") != SUPPORTED_ARCHITECTURE:
        errors.append(f"architecture must be {SUPPORTED_ARCHITECTURE}")
    if not isinstance(document.get("run_id"), int) or document.get("run_id", 0) <= 0:
        errors.append("run_id must be a positive integer")

    archive = document.get("archive")
    if not isinstance(archive, dict):
        errors.append("archive must be an object")
    else:
        if not safe_relative_path(archive.get("name", "")):
            errors.append("archive.name must be a safe relative path")
        _validate_sha(archive.get("sha256"), "archive.sha256", errors)
        if not isinstance(archive.get("size"), int) or archive.get("size", -1) < 0:
            errors.append("archive.size must be a non-negative integer")

    parts = document.get("parts")
    if not isinstance(parts, list) or not parts:
        errors.append("parts must be a non-empty list")
    else:
        seen_names: set[str] = set()
        seen_artifacts: set[str] = set()
        for index, part in enumerate(parts):
            prefix = f"parts[{index}]"
            if not isinstance(part, dict):
                errors.append(f"{prefix} must be an object")
                continue
            name = part.get("name")
            artifact_name = part.get("artifact_name")
            if not safe_relative_path(name or ""):
                errors.append(f"{prefix}.name must be a safe relative path")
            elif name in seen_names:
                errors.append(f"duplicate part name: {name}")
            else:
                seen_names.add(name)
            if not isinstance(artifact_name, str) or not ARTIFACT_SET_RE.fullmatch(artifact_name):
                errors.append(f"{prefix}.artifact_name has an invalid shape")
            elif artifact_name in seen_artifacts:
                errors.append(f"duplicate artifact name: {artifact_name}")
            else:
                seen_artifacts.add(artifact_name)
            _validate_sha(part.get("sha256"), f"{prefix}.sha256", errors)
            size = part.get("size")
            if not isinstance(size, int) or size <= 0 or size > 400 * 1024 * 1024:
                errors.append(f"{prefix}.size must be in 1..400 MiB")
            if part.get("index") != index:
                errors.append(f"{prefix}.index must equal {index}")

    requires = document.get("requires")
    if not isinstance(requires, list) or any(not isinstance(item, str) or not NAME_RE.fullmatch(item) for item in requires):
        errors.append("requires must be a list of profile names")
    elif len(set(requires)) != len(requires):
        errors.append("requires must not contain duplicates")

    for field in ("activation_script", "doctor_script", "software_inventory"):
        if not safe_relative_path(document.get(field, "")):
            errors.append(f"{field} must be a safe relative path")
    optional_project_fields = ("project_cache", "project_prepare_script")
    present_project_fields = [field for field in optional_project_fields if field in document]
    if present_project_fields and len(present_project_fields) != len(optional_project_fields):
        errors.append("project_cache and project_prepare_script must be declared together")
    for field in present_project_fields:
        if not safe_relative_path(document.get(field, "")):
            errors.append(f"{field} must be a safe relative path")

    compatibility = document.get("compatibility")
    if not isinstance(compatibility, dict):
        errors.append("compatibility must be an object")
    else:
        min_restore = compatibility.get("minimum_restore_version")
        if not isinstance(min_restore, int) or min_restore < 1:
            errors.append("compatibility.minimum_restore_version must be positive")

    return errors


def load_and_validate_manifest(path: Path) -> dict[str, Any]:
    document = json.loads(path.read_text(encoding="utf-8"))
    errors = validate_manifest(document)
    if errors:
        raise ValueError("; ".join(errors))
    return document
