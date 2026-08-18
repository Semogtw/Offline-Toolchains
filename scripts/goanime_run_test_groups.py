#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

_GROUPS = ("core", "network", "crawl", "evidence")


def _group_for(path: Path) -> str:
    stem = path.stem.lower()
    if any(token in stem for token in ("fetch", "proxy", "network", "browser")):
        return "network"
    if any(token in stem for token in ("crawler", "parser", "pagination")):
        return "crawl"
    if any(token in stem for token in ("evidence", "sanit", "ownership", "redaction")):
        return "evidence"
    return "core"


def _post_status(*, context: str, state: str, reporter: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(reporter),
            "--state",
            state,
            "--context",
            context,
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _failure_kind(output: str) -> str:
    lowered = output.lower()
    if "modulenotfounderror" in lowered or "importerror" in lowered:
        return "import"
    if "typeerror" in lowered:
        return "type-error"
    if "syntaxerror" in lowered or "indentationerror" in lowered:
        return "syntax"
    if "assertionerror" in lowered or "fail:" in lowered:
        return "assertion"
    if "valueerror" in lowered:
        return "value-error"
    return "runtime"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tests-dir", type=Path, required=True)
    parser.add_argument("--reporter", type=Path, required=True)
    args = parser.parse_args()

    tests_dir = args.tests_dir.resolve()
    pipeline_dir = tests_dir.parent
    reporter = args.reporter.resolve()
    files = sorted(tests_dir.glob("test_*.py"))
    if not files:
        raise SystemExit("no deterministic test files were discovered")

    grouped: dict[str, list[Path]] = {group: [] for group in _GROUPS}
    for path in files:
        grouped[_group_for(path)].append(path)

    failed: list[str] = []
    for group in _GROUPS:
        group_files = grouped[group]
        if not group_files:
            continue
        group_context = f"goanime-scrapling/tests-{group}"
        _post_status(context=group_context, state="pending", reporter=reporter)
        group_failed = False
        first_kind = ""
        first_slot = ""
        for index, path in enumerate(group_files, start=1):
            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "unittest",
                    "discover",
                    "-s",
                    "tests",
                    "-p",
                    path.name,
                ],
                cwd=pipeline_dir,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=os.environ.copy(),
            )
            if result.returncode != 0:
                group_failed = True
                if not first_kind:
                    first_kind = _failure_kind(result.stdout)
                    first_slot = f"{index:02d}"
        state = "failure" if group_failed else "success"
        _post_status(context=group_context, state=state, reporter=reporter)
        if group_failed:
            failed.append(group)
            kind = first_kind or "runtime"
            _post_status(
                context=f"{group_context}-{kind}",
                state="failure",
                reporter=reporter,
            )
            _post_status(
                context=f"{group_context}-slot-{first_slot or '00'}-{kind}",
                state="failure",
                reporter=reporter,
            )
        print(f"{group}: {state}")

    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write(f"failed_groups={','.join(failed)}\n")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
