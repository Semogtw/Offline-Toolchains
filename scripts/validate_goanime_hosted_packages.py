#!/usr/bin/env python3
"""Validate the public exact-version manifest used by the GoAnime toolchain."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import NamedTuple

PACKAGE_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
EXACT_VERSION = re.compile(
    r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)
MAX_PACKAGES = 500


class HostedPackage(NamedTuple):
    name: str
    version: str


def parse_manifest(content: str) -> tuple[HostedPackage, ...]:
    packages: list[HostedPackage] = []
    seen: set[str] = set()

    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.count("=") != 1:
            raise ValueError(f"line {line_number} must be package=version")

        name, version = line.split("=", 1)
        if not PACKAGE_NAME.fullmatch(name):
            raise ValueError(f"line {line_number} has an invalid package name")
        if not EXACT_VERSION.fullmatch(version):
            raise ValueError(f"line {line_number} must contain one exact version")
        if name in seen:
            raise ValueError(f"line {line_number} duplicates package {name}")

        seen.add(name)
        packages.append(HostedPackage(name, version))

    if not packages:
        raise ValueError("manifest must contain at least one hosted package")
    if len(packages) > MAX_PACKAGES:
        raise ValueError(f"manifest exceeds the {MAX_PACKAGES}-package safety limit")

    sorted_names = sorted(item.name for item in packages)
    actual_names = [item.name for item in packages]
    if actual_names != sorted_names:
        raise ValueError("packages must be sorted by name")

    return tuple(packages)


def validate_file(path: Path) -> tuple[HostedPackage, ...]:
    return parse_manifest(path.read_text(encoding="utf-8"))


def main() -> int:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "fixtures/goanime/hosted-packages.txt"
    )
    try:
        packages = validate_file(source)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"invalid GoAnime hosted package manifest: {error}", file=sys.stderr)
        return 2

    print(
        json.dumps(
            {
                "manifest": source.as_posix(),
                "package_count": len(packages),
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
