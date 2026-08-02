#!/usr/bin/env python3
"""Validate and normalize a private source bundle request."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any, TextIO

ALLOWED_PROJECTS = {"goanime", "zapzap", "semogsite", "hydra"}
ALLOWED_MODES = {"full", "ref", "snapshot"}
EXPECTED_KEYS = {"project", "mode", "ref"}
HEX_COMMIT = re.compile(r"^[0-9a-fA-F]{7,40}$")
REF_CHARS = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/+@-]{0,199}$")


def _load(source: str) -> Any:
    stream: TextIO
    if source == "-":
        stream = sys.stdin
        return json.load(stream)
    return json.loads(Path(source).read_text(encoding="utf-8"))


def _validate_ref(value: str) -> None:
    if not value:
        return
    if len(value) > 200:
        raise ValueError("ref must be at most 200 characters")
    if value.startswith("-"):
        raise ValueError("ref must not begin with '-'")
    if any(ord(char) < 32 or ord(char) == 127 or char.isspace() for char in value):
        raise ValueError("ref must not contain whitespace or control characters")
    for forbidden in ("..", "@{", "\\", ":", "^", "~", "?", "*", "["):
        if forbidden in value:
            raise ValueError(f"ref contains forbidden sequence: {forbidden}")
    if value == "@":
        raise ValueError("ref '@' is not allowed")
    if HEX_COMMIT.fullmatch(value):
        return
    if not REF_CHARS.fullmatch(value):
        raise ValueError("ref contains unsupported characters")
    if value.startswith("/") or value.endswith(("/", ".")) or "//" in value:
        raise ValueError("ref has an invalid path shape")
    for component in value.split("/"):
        if not component or component.startswith(".") or component.endswith((".", ".lock")):
            raise ValueError("ref contains an invalid path component")


def validate(data: Any) -> dict[str, str]:
    if not isinstance(data, dict):
        raise ValueError("request must be a JSON object")
    keys = set(data)
    if keys != EXPECTED_KEYS:
        missing = sorted(EXPECTED_KEYS - keys)
        extra = sorted(keys - EXPECTED_KEYS)
        raise ValueError(f"request keys mismatch; missing={missing}, extra={extra}")

    project = data["project"]
    mode = data["mode"]
    ref = data["ref"]
    if not all(isinstance(value, str) for value in (project, mode, ref)):
        raise ValueError("project, mode and ref must be strings")
    if project not in ALLOWED_PROJECTS:
        raise ValueError(f"unsupported project: {project}")
    if mode not in ALLOWED_MODES:
        raise ValueError(f"unsupported mode: {mode}")
    _validate_ref(ref)

    return {"project": project, "mode": mode, "ref": ref}


def main() -> int:
    source = sys.argv[1] if len(sys.argv) > 1 else "-"
    try:
        normalized = validate(_load(source))
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"invalid source bundle request: {error}", file=sys.stderr)
        return 2
    print(json.dumps(normalized, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
