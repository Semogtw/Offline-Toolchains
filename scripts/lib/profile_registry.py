#!/usr/bin/env python3
"""Profile registry loading and dependency expansion."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .artifact_contract import NAME_RE, SUPPORTED_ARCHITECTURE, SUPPORTED_PLATFORM

REQUIRED_KEYS = {
    "name",
    "kind",
    "project",
    "packages",
    "requires",
    "activation_order",
    "lock_mode",
    "lock_inputs",
    "doctor_checks",
    "platform",
    "architecture",
}


def validate_profile(profile: Any, *, filename: str = "<profile>") -> list[str]:
    errors: list[str] = []
    if not isinstance(profile, dict):
        return [f"{filename}: profile must be an object"]
    missing = sorted(REQUIRED_KEYS - set(profile))
    if missing:
        errors.append(f"{filename}: missing keys {missing}")
    name = profile.get("name")
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        errors.append(f"{filename}: invalid name")
    if profile.get("kind") not in {"concrete", "aggregate"}:
        errors.append(f"{filename}: kind must be concrete or aggregate")
    if profile.get("project") not in {None, "goanime", "zapzap"}:
        errors.append(f"{filename}: invalid project")
    packages = profile.get("packages")
    if not isinstance(packages, list) or any(not isinstance(item, str) or not NAME_RE.fullmatch(item) for item in packages):
        errors.append(f"{filename}: packages must be profile-safe names")
    if profile.get("kind") == "concrete" and len(packages or []) != 1:
        errors.append(f"{filename}: concrete profile must declare exactly one package")
    if profile.get("kind") == "aggregate" and packages:
        errors.append(f"{filename}: aggregate profile must not publish packages")
    requires = profile.get("requires")
    if not isinstance(requires, list) or any(not isinstance(item, str) or not NAME_RE.fullmatch(item) for item in requires):
        errors.append(f"{filename}: invalid requires")
    elif len(set(requires)) != len(requires):
        errors.append(f"{filename}: duplicate requires")
    order = profile.get("activation_order")
    if not isinstance(order, int) or order < 0:
        errors.append(f"{filename}: activation_order must be non-negative")
    if profile.get("lock_mode") not in {"synthetic", "private-exact", "not-applicable", "aggregate"}:
        errors.append(f"{filename}: invalid lock_mode")
    if not isinstance(profile.get("lock_inputs"), list) or any(not isinstance(item, str) for item in profile.get("lock_inputs", [])):
        errors.append(f"{filename}: lock_inputs must be strings")
    checks = profile.get("doctor_checks")
    if not isinstance(checks, list) or any(not isinstance(item, dict) for item in checks):
        errors.append(f"{filename}: doctor_checks must be objects")
    if profile.get("platform") != SUPPORTED_PLATFORM:
        errors.append(f"{filename}: unsupported platform")
    if profile.get("architecture") != SUPPORTED_ARCHITECTURE:
        errors.append(f"{filename}: unsupported architecture")
    return errors


def load_profiles(root: Path) -> dict[str, dict[str, Any]]:
    registry: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for path in sorted(root.glob("*.json")):
        try:
            profile = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"{path.name}: {error}")
            continue
        errors.extend(validate_profile(profile, filename=path.name))
        name = profile.get("name") if isinstance(profile, dict) else None
        if isinstance(name, str):
            if name in registry:
                errors.append(f"duplicate profile name: {name}")
            registry[name] = profile
    if errors:
        raise ValueError("; ".join(errors))
    for name, profile in registry.items():
        for dependency in profile["requires"]:
            if dependency not in registry:
                errors.append(f"{name}: unknown dependency {dependency}")
    if errors:
        raise ValueError("; ".join(errors))
    for name in registry:
        expand_profile(name, registry)
    return registry


def expand_profile(name: str, registry: dict[str, dict[str, Any]]) -> list[str]:
    if name not in registry:
        raise KeyError(f"unknown profile: {name}")
    result: list[str] = []
    visiting: list[str] = []
    visited: set[str] = set()

    def visit(current: str) -> None:
        if current in visiting:
            cycle = " -> ".join([*visiting, current])
            raise ValueError(f"profile dependency cycle: {cycle}")
        if current in visited:
            return
        visiting.append(current)
        dependencies = sorted(
            registry[current]["requires"],
            key=lambda item: (registry[item]["activation_order"], item),
        )
        for dependency in dependencies:
            visit(dependency)
        visiting.pop()
        visited.add(current)
        if registry[current]["kind"] == "concrete":
            result.append(current)

    visit(name)
    return result
