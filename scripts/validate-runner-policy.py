#!/usr/bin/env python3
"""Enforce the repository policy for GitHub Actions runner selection.

Self-hosted runners are intentionally reserved for release workflows. Regular
CI, validation, cache/materialization, maintenance, and tooling jobs must run
on GitHub-hosted runners.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
RUNS_ON = re.compile(r"^(?P<indent>\s*)runs-on\s*:\s*(?P<value>.*)$")
TOP_LEVEL_NAME = re.compile(r"^name\s*:\s*(?P<value>.+?)\s*$", re.IGNORECASE)


def is_release_workflow(path: Path, text: str) -> bool:
    if "release" in path.name.lower():
        return True
    for line in text.splitlines():
        match = TOP_LEVEL_NAME.match(line)
        if match:
            return "release" in match.group("value").lower()
    return False


def self_hosted_runner_lines(text: str) -> list[int]:
    lines = text.splitlines()
    hits: list[int] = []

    for index, line in enumerate(lines):
        match = RUNS_ON.match(line)
        if not match:
            continue

        value = match.group("value")
        if "self-hosted" in value:
            hits.append(index + 1)
            continue

        # Support block-list runner declarations, for example:
        # runs-on:
        #   - self-hosted
        #   - linux
        if value.strip():
            continue

        base_indent = len(match.group("indent"))
        for nested_index in range(index + 1, len(lines)):
            nested = lines[nested_index]
            if not nested.strip() or nested.lstrip().startswith("#"):
                continue
            nested_indent = len(nested) - len(nested.lstrip())
            if nested_indent <= base_indent:
                break
            if "self-hosted" in nested:
                hits.append(nested_index + 1)

    return hits


def main() -> int:
    violations: list[str] = []
    for path in sorted(WORKFLOWS.glob("*.y*ml")):
        text = path.read_text(encoding="utf-8")
        hits = self_hosted_runner_lines(text)
        if hits and not is_release_workflow(path, text):
            rel = path.relative_to(ROOT)
            for line in hits:
                violations.append(f"{rel}:{line}: self-hosted runner is reserved for release workflows")

    if violations:
        print("runner policy: FAIL", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    print("runner policy: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
