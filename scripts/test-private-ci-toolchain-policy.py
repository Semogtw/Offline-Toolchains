#!/usr/bin/env python3
"""Verify project-specific toolchain and runner policy in the private CI hub."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS_DIR = ROOT / ".github/workflows"
PRIVATE_CI_WORKFLOW = WORKFLOWS_DIR / "run-private-project-ci.yml"
MANGA_AVAILABILITY_WORKFLOW = (
    WORKFLOWS_DIR / "run-goanime-manga-availability-private-ci.yml"
)

RUNS_ON_RE = re.compile(r"^(?P<indent>\s*)runs-on:\s*(?P<value>.*)$")
WORKFLOW_NAME_RE = re.compile(r"^name:\s*(?P<name>.+?)\s*$")


def workflow_name(text: str, fallback: str) -> str:
    for line in text.splitlines():
        match = WORKFLOW_NAME_RE.match(line)
        if match:
            return match.group("name").strip().strip("\"'")
    return fallback


def runs_on_values(text: str) -> list[str]:
    """Return every runs-on scalar/list block without parsing unrelated YAML."""
    lines = text.splitlines()
    values: list[str] = []

    for index, line in enumerate(lines):
        match = RUNS_ON_RE.match(line)
        if not match:
            continue

        indent = len(match.group("indent").expandtabs(2))
        parts = [match.group("value").strip()]
        cursor = index + 1

        while cursor < len(lines):
            candidate = lines[cursor]
            if not candidate.strip():
                cursor += 1
                continue

            candidate_indent = len(candidate) - len(candidate.lstrip(" \t"))
            if candidate_indent <= indent:
                break

            parts.append(candidate.strip())
            cursor += 1

        values.append(" ".join(part for part in parts if part))

    return values


def is_release_workflow(path: Path, text: str) -> bool:
    descriptor = f"{path.stem} {workflow_name(text, path.stem)}".lower()
    return "release" in descriptor


def assert_self_hosted_is_release_only() -> None:
    violations: list[str] = []

    for path in sorted((*WORKFLOWS_DIR.glob("*.yml"), *WORKFLOWS_DIR.glob("*.yaml"))):
        text = path.read_text(encoding="utf-8")
        if not any("self-hosted" in value.lower() for value in runs_on_values(text)):
            continue
        if not is_release_workflow(path, text):
            violations.append(str(path.relative_to(ROOT)))

    if violations:
        joined = ", ".join(violations)
        raise SystemExit(
            "private CI runner policy: FAIL: self-hosted runner is reserved for "
            f"release workflows; found in {joined}"
        )


workflow = PRIVATE_CI_WORKFLOW.read_text(encoding="utf-8")

try:
    goanime = workflow.split("\n  goanime:\n", 1)[1].split("\n  zapzap:\n", 1)[0]
    zapzap = workflow.split("\n  zapzap:\n", 1)[1].split("\n  semogsite:\n", 1)[0]
except IndexError as exc:
    raise SystemExit("private CI toolchain policy: FAIL: project job boundary missing") from exc

assert "name: Set up Temurin JDK 17" in goanime
assert 'java-version: "17"' in goanime
assert "name: Set up Temurin JDK 21" in zapzap
assert 'java-version: "21"' in zapzap
assert "name: Set up Temurin JDK 17" not in zapzap
assert 'java-version: "17"' not in zapzap

availability = MANGA_AVAILABILITY_WORKFLOW.read_text(encoding="utf-8")
assert "runs-on: ubuntu-24.04" in availability
assert not any(
    "self-hosted" in value.lower() for value in runs_on_values(availability)
)

# Parser contract: inline and list self-hosted labels must be detected, while
# unrelated branch names containing "self-hosted" must not count as a runner.
assert runs_on_values("jobs:\n  test:\n    runs-on: [self-hosted, linux]\n") == [
    "[self-hosted, linux]"
]
assert runs_on_values(
    "jobs:\n  test:\n    runs-on:\n      - self-hosted\n      - linux\n"
) == ["- self-hosted - linux"]
assert not any(
    "self-hosted" in value.lower()
    for value in runs_on_values(
        "env:\n  TARGET_BRANCH: feat/self-hosted-metadata-api\n"
    )
)

assert_self_hosted_is_release_only()

print("private CI toolchain and runner policy: PASS")
