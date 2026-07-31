#!/usr/bin/env python3
"""Capture and seed portable Dart/Flutter native-asset shared caches."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import sys
from pathlib import Path
from typing import Any


def _ephemeral(path: Path) -> bool:
    return path.name == ".lock" or path.name.endswith(".tmp")


def _copy_tree(source: Path, destination: Path) -> tuple[int, int]:
    files = 0
    bytes_copied = 0
    destination.mkdir(parents=True, exist_ok=True)
    with os.scandir(source) as entries:
        for entry in sorted(entries, key=lambda item: item.name):
            source_entry = Path(entry.path)
            destination_entry = destination / entry.name
            if source_entry.is_symlink():
                raise ValueError(f"native-asset cache must not contain symlinks: {source_entry}")
            mode = entry.stat(follow_symlinks=False).st_mode
            if stat.S_ISDIR(mode):
                child_files, child_bytes = _copy_tree(source_entry, destination_entry)
                files += child_files
                bytes_copied += child_bytes
                if child_files == 0:
                    destination_entry.rmdir()
            elif stat.S_ISREG(mode):
                if _ephemeral(source_entry):
                    continue
                destination_entry.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source_entry, destination_entry, follow_symlinks=False)
                files += 1
                bytes_copied += destination_entry.stat().st_size
            else:
                raise ValueError(f"unsupported native-asset cache entry: {source_entry}")
    return files, bytes_copied


def capture_cache(source: Path, destination: Path) -> dict[str, Any]:
    source = source.resolve()
    destination = destination.absolute()
    if not source.is_dir():
        raise ValueError(f"native-asset shared cache not found: {source}")
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"capture destination already exists: {destination}")
    files, bytes_copied = _copy_tree(source, destination)
    if files == 0 or bytes_copied == 0:
        shutil.rmtree(destination, ignore_errors=True)
        raise ValueError("native-asset shared cache contains no completed files")
    return {"mode": "capture", "files": files, "bytes": bytes_copied, "destination": str(destination)}


def prepare_project_cache(cache: Path, project: Path) -> dict[str, Any]:
    cache = cache.resolve()
    project = project.resolve()
    if not cache.is_dir():
        raise ValueError(f"portable native-asset cache not found: {cache}")
    if not (project / "pubspec.yaml").is_file():
        raise ValueError(f"project pubspec.yaml not found: {project}")
    destination = project / ".dart_tool" / "hooks_runner" / "shared"
    if destination.is_symlink():
        raise ValueError(f"project shared cache destination is a symlink: {destination}")
    files, bytes_copied = _copy_tree(cache, destination)
    if files == 0 or bytes_copied == 0:
        raise ValueError("portable native-asset cache contains no completed files")
    return {"mode": "prepare", "files": files, "bytes": bytes_copied, "destination": str(destination)}


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    capture = subparsers.add_parser("capture")
    capture.add_argument("--source", type=Path, required=True)
    capture.add_argument("--destination", type=Path, required=True)
    prepare = subparsers.add_parser("prepare")
    prepare.add_argument("--cache", type=Path, required=True)
    prepare.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = (
            capture_cache(args.source, args.destination)
            if args.command == "capture"
            else prepare_project_cache(args.cache, args.project)
        )
    except (OSError, ValueError) as error:
        print(f"native-asset cache operation failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
