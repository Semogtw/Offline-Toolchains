#!/usr/bin/env python3
"""Verify SemogSite uses only the reviewed strict install path in private CI."""

from pathlib import Path

workflow = (
    Path(__file__).resolve().parents[1]
    / ".github/workflows/run-private-project-ci.yml"
).read_text(encoding="utf-8")

try:
    tail = workflow.split("\n  semogsite:\n", 1)[1]
    semogsite = tail.split("\n  hydra:\n", 1)[0]
except IndexError as exc:
    raise SystemExit("SemogSite install policy: FAIL: project job boundary missing") from exc

required = (
    "Set up Node.js 22 without persistent dependency cache",
    'node-version: "22"',
    "check-latest: false",
    "Activate repository-pinned pnpm",
    "packageManager",
    "pnpm@*) ;;",
    'corepack prepare "$package_manager" --activate',
    "Configure reviewed CI-only native build",
    "onlyBuiltDependencies:",
    "- better-sqlite3",
    "pnpm install --frozen-lockfile",
    "Verify native SQLite dependency",
    "better_sqlite3.node",
    "pnpm check:boundaries",
    "pnpm check:public-confidentiality",
    "pnpm check",
    "playwright test tests/e2e/workflow-orchestration.spec.ts",
    "Remove private checkout",
    'rm -rf "$GITHUB_WORKSPACE/private-source"',
)
for fragment in required:
    if fragment not in semogsite:
        raise SystemExit(
            f"SemogSite install policy: FAIL: missing required fragment {fragment!r}"
        )

for fragment in (
    "pnpm install --no-frozen-lockfile",
    "bootstrap mode",
    "actions/cache@",
    "cache: pnpm",
    "persist-credentials: true",
):
    if fragment in semogsite:
        raise SystemExit(
            f"SemogSite install policy: FAIL: forbidden fragment present {fragment!r}"
        )

if semogsite.count("pnpm install --frozen-lockfile") != 1:
    raise SystemExit(
        "SemogSite install policy: FAIL: frozen install must appear exactly once"
    )

print("SemogSite install policy: PASS")
