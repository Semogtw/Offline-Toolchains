#!/usr/bin/env python3
"""Fail-closed validation for generation continuation dispatch inputs."""

from __future__ import annotations

import argparse
import re
import sys


RUN_ID = re.compile(r"^[1-9][0-9]*$")
INDEX = re.compile(r"^[0-9]+$")


def validate_continuation_request(
    *, parent_run_id: str, reference_runtime_run_id: str, continuation_index: str
) -> None:
    if INDEX.fullmatch(continuation_index) is None:
        raise ValueError("continuation_index is invalid")
    if parent_run_id and RUN_ID.fullmatch(parent_run_id) is None:
        raise ValueError("parent_run_id is invalid")
    if reference_runtime_run_id and RUN_ID.fullmatch(reference_runtime_run_id) is None:
        raise ValueError("reference_runtime_run_id is invalid")

    index = int(continuation_index)
    if index > 0:
        if not RUN_ID.fullmatch(parent_run_id or "") or not RUN_ID.fullmatch(
            reference_runtime_run_id or ""
        ):
            raise ValueError(
                "continuation_index > 0 requires valid parent_run_id and "
                "reference_runtime_run_id"
            )
        return

    if bool(parent_run_id) != bool(reference_runtime_run_id):
        raise ValueError(
            "parent_run_id and reference_runtime_run_id must be supplied together"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate identity-bound Yuzono audit continuation inputs."
    )
    parser.add_argument("--parent-run-id", required=True)
    parser.add_argument("--reference-runtime-run-id", required=True)
    parser.add_argument("--continuation-index", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        validate_continuation_request(
            parent_run_id=args.parent_run_id,
            reference_runtime_run_id=args.reference_runtime_run_id,
            continuation_index=args.continuation_index,
        )
    except ValueError as error:
        print(f"continuation request rejected: {error}", file=sys.stderr)
        return 1
    print("continuation request accepted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
