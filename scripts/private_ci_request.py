#!/usr/bin/env python3
"""Validate and normalize requests for public CI of allowlisted projects."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

PROJECTS: dict[str, dict[str, str]] = {
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
        "default_ref": "main",
    },
    "hydra": {
        "repository": "Semogtw/HydraPersonalizado",
        "default_ref": "main",
    },
    "receitas": {
        "repository": "Semogtw/Receitas",
        "default_ref": "main",
    },
    "fichario": {
        "repository": "Semogtw/FicharioVirtual",
        "default_ref": "main",
    },
}

_ALLOWED_KEYS = frozenset({"project", "ref"})
_REF_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$")


class RequestValidationError(ValueError):
    """Raised when an incoming CI request is not safe or supported."""


def _validate_ref(ref: Any) -> str:
    if not isinstance(ref, str):
        raise RequestValidationError("ref must be a string")
    if not _REF_PATTERN.fullmatch(ref):
        raise RequestValidationError(
            "ref must be 1-200 characters and contain only ASCII letters, "
            "digits, '.', '_', '/', or '-'"
        )
    if (
        ".." in ref
        or "@{" in ref
        or "//" in ref
        or "\\" in ref
        or ref.endswith("/")
        or ref.endswith(".")
        or ref.endswith(".lock")
        or ref.startswith("-")
    ):
        raise RequestValidationError("ref contains a forbidden Git ref sequence")
    return ref


def normalize_request(payload: Any) -> dict[str, str]:
    """Return a fixed repository/ref mapping for a validated request payload."""
    if not isinstance(payload, dict):
        raise RequestValidationError("request must be a JSON object")

    unknown_keys = set(payload) - _ALLOWED_KEYS
    if unknown_keys:
        unknown = ", ".join(sorted(str(key) for key in unknown_keys))
        raise RequestValidationError(f"unsupported request fields: {unknown}")

    project = payload.get("project")
    if not isinstance(project, str) or project not in PROJECTS:
        allowed = ", ".join(PROJECTS)
        raise RequestValidationError(f"project must be one of: {allowed}")

    project_config = PROJECTS[project]
    requested_ref = payload.get("ref", "")
    if requested_ref == "":
        ref = project_config["default_ref"]
    else:
        ref = _validate_ref(requested_ref)

    return {
        "project": project,
        "repository": project_config["repository"],
        "ref": ref,
        "default_ref": project_config["default_ref"],
    }


def load_and_normalize(path: Path) -> dict[str, str]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RequestValidationError(f"request file does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise RequestValidationError(
            f"request file is not valid JSON: line {exc.lineno}, column {exc.colno}"
        ) from exc
    return normalize_request(payload)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate and normalize an allowlisted CI request."
    )
    parser.add_argument("request_file", type=Path)
    args = parser.parse_args(argv)

    try:
        normalized = load_and_normalize(args.request_file)
    except RequestValidationError as exc:
        print(f"CI request rejected: {exc}", file=sys.stderr)
        return 2

    print(json.dumps(normalized, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
