#!/usr/bin/env python3
"""Validate public artifact metadata for the portable GoAnime toolchain."""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PREFIX = "goanime-flutter-cache-linux-x64-"
PART_PATTERN = re.compile(r"-part-(\d{2})$")
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")


def _parse_utc(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a non-empty UTC timestamp")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise ValueError(f"{field} must be an ISO-8601 timestamp") from error
    if parsed.tzinfo is None:
        raise ValueError(f"{field} must include a timezone")
    return parsed.astimezone(timezone.utc)


def _positive_int(value: Any, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError(f"{field} must be a positive integer")
    return value


def verify_receipt(path: Path, *, now: datetime | None = None) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ValueError(f"unable to read receipt ({type(error).__name__})") from error
    except json.JSONDecodeError as error:
        raise ValueError(
            f"receipt is invalid JSON at line {error.lineno}, column {error.colno}"
        ) from error

    if not isinstance(payload, dict):
        raise ValueError("receipt must contain a JSON object")
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported receipt schema_version")

    run_id = _positive_int(payload.get("run_id"), "run_id")
    expected_url = (
        "https://github.com/Semogtw/Offline-Toolchains/actions/runs/" f"{run_id}"
    )
    if payload.get("run_url") != expected_url:
        raise ValueError("run_url does not match run_id or repository")

    head_sha = payload.get("workflow_head_sha")
    if not isinstance(head_sha, str) or not SHA_PATTERN.fullmatch(head_sha):
        raise ValueError("workflow_head_sha must be a lowercase 40-character SHA")
    if payload.get("workflow_event") not in {"push", "workflow_dispatch"}:
        raise ValueError("workflow_event must be push or workflow_dispatch")
    _parse_utc(payload.get("recorded_at_utc"), "recorded_at_utc")

    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ValueError("artifacts must be a non-empty list")

    effective_now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    ids: set[int] = set()
    names: set[str] = set()
    manifests: list[dict[str, Any]] = []
    parts: list[tuple[int, dict[str, Any]]] = []

    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict):
            raise ValueError(f"artifact {index} must be an object")
        artifact_id = _positive_int(artifact.get("artifact_id"), "artifact_id")
        if artifact_id in ids:
            raise ValueError(f"duplicate artifact_id: {artifact_id}")
        ids.add(artifact_id)

        name = artifact.get("name")
        if not isinstance(name, str) or not name.startswith(PREFIX):
            raise ValueError(f"artifact {index} is not a GoAnime toolchain artifact")
        if name in names:
            raise ValueError(f"duplicate artifact name: {name}")
        names.add(name)

        _positive_int(artifact.get("size_bytes"), "size_bytes")
        if artifact.get("expired") is not False:
            raise ValueError(f"artifact {name} is expired")
        _parse_utc(artifact.get("created_at"), f"{name}.created_at")
        expires_at = _parse_utc(artifact.get("expires_at"), f"{name}.expires_at")
        if expires_at <= effective_now:
            raise ValueError(f"artifact {name} expires_at is not in the future")

        if name == f"{PREFIX}manifest":
            manifests.append(artifact)
            continue
        match = PART_PATTERN.search(name)
        if match is None:
            raise ValueError(f"unexpected GoAnime toolchain artifact name: {name}")
        parts.append((int(match.group(1)), artifact))

    if len(manifests) != 1:
        raise ValueError("receipt must contain exactly one manifest artifact")
    if not parts:
        raise ValueError("receipt must contain at least one bundle part")

    parts.sort(key=lambda item: item[0])
    actual = [number for number, _ in parts]
    expected = list(range(len(parts)))
    if actual != expected:
        raise ValueError(
            "bundle part numbers must be contiguous from 00; " f"found {actual}"
        )

    return {
        "run_id": run_id,
        "run_url": expected_url,
        "workflow_head_sha": head_sha,
        "manifest_artifact_id": manifests[0]["artifact_id"],
        "manifest_artifact_name": manifests[0]["name"],
        "part_artifact_ids": [artifact["artifact_id"] for _, artifact in parts],
        "part_artifact_names": [artifact["name"] for _, artifact in parts],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("receipt", type=Path)
    arguments = parser.parse_args(argv)
    try:
        result = verify_receipt(arguments.receipt)
    except ValueError as error:
        print(f"Invalid GoAnime toolchain receipt: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
