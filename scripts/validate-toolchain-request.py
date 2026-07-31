#!/usr/bin/env python3
"""Validate and normalize connector toolchain requests."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.lib.profile_registry import expand_profile, load_profiles

EXPECTED_KEYS = {"profile", "force_rebuild"}


def validate(data: Any, profiles_root: Path) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError("request must be a JSON object")
    keys = set(data)
    if keys != EXPECTED_KEYS:
        raise ValueError(f"request keys mismatch; missing={sorted(EXPECTED_KEYS - keys)}, extra={sorted(keys - EXPECTED_KEYS)}")
    profile = data["profile"]
    force_rebuild = data["force_rebuild"]
    if not isinstance(profile, str):
        raise ValueError("profile must be a string")
    if not isinstance(force_rebuild, bool):
        raise ValueError("force_rebuild must be a boolean")
    registry = load_profiles(profiles_root)
    if profile not in registry:
        raise ValueError(f"unsupported profile: {profile}")
    selected = registry[profile]
    concrete = expand_profile(profile, registry)
    project = selected["project"]
    project_values = {registry[name]["project"] for name in concrete if registry[name]["project"] is not None}
    if len(project_values) > 1:
        raise ValueError("profile spans multiple private projects")
    if project is None and project_values:
        project = next(iter(project_values))
    return {
        "schema_version": 1,
        "profile": profile,
        "force_rebuild": force_rebuild,
        "project": project,
        "concrete_profiles": concrete,
        "private_profiles": [name for name in concrete if registry[name]["project"] is not None],
        "public_profiles": [name for name in concrete if registry[name]["project"] is None],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("request", nargs="?", default="-")
    parser.add_argument("--profiles", type=Path, default=Path(__file__).resolve().parents[1] / "profiles")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        if args.request == "-":
            data = json.load(sys.stdin)
        else:
            data = json.loads(Path(args.request).read_text(encoding="utf-8"))
        normalized = validate(data, args.profiles.resolve())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"invalid toolchain request: {error}", file=sys.stderr)
        return 2
    rendered = json.dumps(normalized, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    print(json.dumps(normalized, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
