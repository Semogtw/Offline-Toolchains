#!/usr/bin/env python3
"""Verify SemogSite uses frozen installs except for documented bootstrap refs."""

from pathlib import Path

workflow = (
    Path(__file__).resolve().parents[1]
    / ".github/workflows/run-private-project-ci.yml"
).read_text(encoding="utf-8")

try:
    semogsite = workflow.split("\n  semogsite:\n", 1)[1]
except IndexError as exc:
    raise SystemExit("SemogSite install policy: FAIL: project job boundary missing") from exc

required = (
    "if [[ -f pnpm-lock.yaml ]]; then",
    "pnpm install --frozen-lockfile",
    "pnpm install --no-frozen-lockfile",
    "pnpm-lock.yaml is absent; using the documented bootstrap mode.",
    'echo "mode=frozen" >> "$GITHUB_OUTPUT"',
    'echo "mode=bootstrap" >> "$GITHUB_OUTPUT"',
    "Dependency mode:",
)
for fragment in required:
    if fragment not in semogsite:
        raise SystemExit(
            f"SemogSite install policy: FAIL: missing required fragment {fragment!r}"
        )

if semogsite.count("pnpm install --no-frozen-lockfile") != 1:
    raise SystemExit(
        "SemogSite install policy: FAIL: bootstrap install must appear exactly once"
    )

print("SemogSite install policy: PASS")
