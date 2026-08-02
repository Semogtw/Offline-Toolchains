#!/usr/bin/env python3
"""Verify project-specific runtime policy in the private CI workflow."""

from pathlib import Path

workflow = (
    Path(__file__).resolve().parents[1]
    / ".github/workflows/run-private-project-ci.yml"
).read_text(encoding="utf-8")

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

print("private CI toolchain policy: PASS")
