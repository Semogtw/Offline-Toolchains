#!/usr/bin/env python3
"""Copy a directory into a portable tree without retaining symbolic links."""
from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path


def _copy_directory(source: Path, destination: Path, ancestors: frozenset[Path]) -> None:
    resolved = source.resolve(strict=True)
    if resolved in ancestors:
        raise ValueError(f"symbolic-link cycle detected at: {source}")
    destination.mkdir()
    next_ancestors = ancestors | {resolved}

    with os.scandir(source) as entries:
        for entry in entries:
            source_entry = Path(entry.path)
            destination_entry = destination / entry.name
            if source_entry.is_symlink():
                try:
                    target = source_entry.resolve(strict=True)
                except FileNotFoundError:
                    continue
                if target.is_dir():
                    _copy_directory(target, destination_entry, next_ancestors)
                elif target.is_file():
                    shutil.copy2(target, destination_entry)
                else:
                    raise ValueError(f"unsupported symbolic-link target: {source_entry}")
            elif entry.is_dir(follow_symlinks=False):
                _copy_directory(source_entry, destination_entry, next_ancestors)
            elif entry.is_file(follow_symlinks=False):
                shutil.copy2(source_entry, destination_entry)
            else:
                raise ValueError(f"unsupported filesystem entry: {source_entry}")

    shutil.copystat(source, destination, follow_symlinks=True)


def copy_portable_tree(source: Path, destination: Path) -> None:
    source = source.resolve()
    destination = destination.absolute()
    if not source.is_dir():
        raise ValueError(f"source directory not found: {source}")
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"destination already exists: {destination}")
    try:
        destination.resolve().relative_to(source)
    except ValueError:
        pass
    else:
        raise ValueError("destination must not be inside source")

    _copy_directory(source, destination, frozenset())
    retained = next((path for path in destination.rglob("*") if path.is_symlink()), None)
    if retained is not None:
        raise ValueError(f"portable copy retained a symbolic link: {retained}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        copy_portable_tree(args.source, args.destination)
    except (OSError, ValueError) as error:
        print(f"portable tree copy failed: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
