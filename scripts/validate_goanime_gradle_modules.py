#!/usr/bin/env python3
"""Validate the public exact-coordinate manifest for the GoAnime Gradle delta."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PART = r"[A-Za-z0-9_.-]+"
VERSION = r"[0-9A-Za-z][0-9A-Za-z.+-]*"
COORDINATE = re.compile(rf"^{PART}:{PART}:{VERSION}$")
MAX_COORDINATES = 100


def parse_manifest(content: str) -> tuple[str, ...]:
    coordinates: list[str] = []
    seen: set[str] = set()
    for line_number, raw in enumerate(content.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if not COORDINATE.fullmatch(line):
            raise ValueError(
                f"line {line_number} must be group:artifact:exact-version"
            )
        if line in seen:
            raise ValueError(f"line {line_number} duplicates {line}")
        seen.add(line)
        coordinates.append(line)
    if not coordinates:
        raise ValueError("manifest must contain at least one coordinate")
    if len(coordinates) > MAX_COORDINATES:
        raise ValueError(f"manifest exceeds {MAX_COORDINATES} coordinates")
    if coordinates != sorted(coordinates):
        raise ValueError("coordinates must be sorted")
    return tuple(coordinates)


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "manifests/goanime/gradle-modules.txt"
    )
    try:
        coordinates = parse_manifest(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"invalid GoAnime Gradle module manifest: {error}", file=sys.stderr)
        return 2
    print(
        json.dumps(
            {
                "manifest": path.as_posix(),
                "coordinate_count": len(coordinates),
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
