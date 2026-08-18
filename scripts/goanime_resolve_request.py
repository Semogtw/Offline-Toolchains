#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Iterable

_SHA40 = re.compile(r"^[0-9a-f]{40}$")
_ALLOWED_KEYS = frozenset({"target_branch", "source_hint", "reason"})


def _changed_paths(event: dict[str, object]) -> tuple[set[str], set[str]]:
    changed: set[str] = set()
    removed: set[str] = set()

    commits = event.get("commits")
    if isinstance(commits, list):
        for raw_commit in commits:
            if not isinstance(raw_commit, dict):
                continue
            for key in ("added", "modified"):
                values = raw_commit.get(key)
                if isinstance(values, list):
                    changed.update(str(value) for value in values)
            values = raw_commit.get("removed")
            if isinstance(values, list):
                removed.update(str(value) for value in values)

    head_commit = event.get("head_commit")
    if isinstance(head_commit, dict):
        for key in ("added", "modified"):
            values = head_commit.get(key)
            if isinstance(values, list):
                changed.update(str(value) for value in values)
        values = head_commit.get("removed")
        if isinstance(values, list):
            removed.update(str(value) for value in values)

    return changed, removed


def _git_changed_paths(workspace: Path) -> tuple[set[str], set[str]]:
    """Read the triggering commit's path changes from the trusted checkout.

    GitHub push payloads can omit or truncate the useful per-commit path lists.
    The checked-out Toolchains commit is the stronger source of truth whenever
    its parent is available (workflows using this helper fetch depth >= 2).
    """
    result = subprocess.run(
        [
            "git",
            "-C",
            str(workspace),
            "diff",
            "--name-status",
            "--no-renames",
            "HEAD^",
            "HEAD",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return set(), set()

    changed: set[str] = set()
    removed: set[str] = set()
    for raw_line in result.stdout.splitlines():
        if not raw_line.strip() or "\t" not in raw_line:
            continue
        status, path = raw_line.split("\t", 1)
        path = path.strip()
        if not path:
            continue
        if status.startswith("D"):
            removed.add(path)
        else:
            changed.add(path)
    return changed, removed


def _is_request_path(path: str, request_dir: str) -> bool:
    prefix = request_dir.rstrip("/") + "/"
    if not path.startswith(prefix) or not path.endswith(".request"):
        return False
    tail = path[len(prefix) :]
    return bool(tail) and "/" not in tail


def _parse_request(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise SystemExit("refresh request contains a malformed line")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key not in _ALLOWED_KEYS:
            raise SystemExit(f"refresh request contains an unknown key: {key}")
        if key in values:
            raise SystemExit(f"refresh request contains a duplicate key: {key}")
        values[key] = value
    return values


def _validate_branch(branch: str) -> None:
    if not branch:
        raise SystemExit("refresh request is missing target_branch")
    result = subprocess.run(
        ["git", "check-ref-format", "--branch", branch],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit("refresh request target_branch is invalid")


def _write_outputs(values: Iterable[tuple[str, str]]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT", "")
    if not output_path:
        raise SystemExit("GITHUB_OUTPUT is missing")
    with open(output_path, "a", encoding="utf-8") as output:
        for key, value in values:
            output.write(f"{key}={value}\n")


def resolve_push_request(
    *,
    event: dict[str, object],
    workspace: Path,
    request_dir: str,
) -> tuple[str, str]:
    event_changed, event_removed = _changed_paths(event)
    git_changed, git_removed = _git_changed_paths(workspace)
    changed = event_changed | git_changed
    removed = event_removed | git_removed

    removed_requests = sorted(
        path for path in removed if _is_request_path(path, request_dir)
    )
    if removed_requests:
        raise SystemExit("deleting a refresh request cannot trigger a provider crawl")

    request_paths = sorted(
        path for path in changed if _is_request_path(path, request_dir)
    )
    if len(request_paths) != 1:
        raise SystemExit(
            f"expected exactly one added/modified refresh request, got {len(request_paths)}"
        )

    request_path = workspace / request_paths[0]
    values = _parse_request(request_path)
    target_branch = values.get("target_branch", "")
    source_hint = values.get("source_hint", "").lower()
    _validate_branch(target_branch)
    if not _SHA40.fullmatch(source_hint):
        raise SystemExit("refresh request source_hint must be a full 40-character SHA")
    return target_branch, source_hint


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request-dir", required=True)
    parser.add_argument("--workspace", type=Path, default=Path("."))
    parser.add_argument("--default-branch", default="feat/scrapling-provider-pipeline")
    parser.add_argument("--dispatch-target", default="")
    args = parser.parse_args()

    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    if event_name == "push":
        event_path = os.environ.get("GITHUB_EVENT_PATH", "")
        if not event_path:
            raise SystemExit("GITHUB_EVENT_PATH is missing")
        event = json.loads(Path(event_path).read_text(encoding="utf-8"))
        if not isinstance(event, dict):
            raise SystemExit("GitHub event payload must be an object")
        target_branch, source_hint = resolve_push_request(
            event=event,
            workspace=args.workspace,
            request_dir=args.request_dir,
        )
    else:
        target_branch = args.dispatch_target.strip() or args.default_branch
        _validate_branch(target_branch)
        source_hint = ""

    _write_outputs(
        (
            ("target_branch", target_branch),
            ("source_hint", source_hint),
        )
    )
    print(f"Refresh target resolved: {target_branch}")
    print(
        "Source revision is pinned by request."
        if source_hint
        else "Source revision will be pinned after checkout."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
