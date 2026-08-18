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


def _post_status(*, group: str, state: str, reporter: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(reporter),
            "--state",
            state,
            "--context",
            f"goanime-scrapling/tests-{group}",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tests-dir", type=Path, required=True)
    parser.add_argument("--reporter", type=Path, required=True)
    args = parser.parse_args()

    tests_dir = args.tests_dir.resolve()
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
        _post_status(group=group, state="pending", reporter=reporter)
        group_failed = False
        for path in group_files:
            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "unittest",
                    "discover",
                    "-s",
                    str(tests_dir),
                    "-p",
                    path.name,
                ],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=os.environ.copy(),
            )
            if result.returncode != 0:
                group_failed = True
        state = "failure" if group_failed else "success"
        _post_status(group=group, state=state, reporter=reporter)
        print(f"{group}: {state}")
        if group_failed:
            failed.append(group)

    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write(f"failed_groups={','.join(failed)}\n")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
