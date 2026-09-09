#!/usr/bin/env python3
"""Validate trailing whitespace on added Markdown diff lines.

Exactly two trailing ASCII spaces are allowed because Markdown uses them as an
explicit hard line break. All other trailing spaces/tabs on added lines fail.
The script consumes a unified diff on stdin.
"""

from __future__ import annotations

import re
import sys


_TRAILING = re.compile(r"[ \t]+$")


def violations(lines: list[str]) -> list[str]:
    failures: list[str] = []
    current_file = "<unknown>"
    new_line = 0

    for raw in lines:
        line = raw.rstrip("\n")
        if line.startswith("+++ b/"):
            current_file = line[6:]
            continue
        if line.startswith("@@"):
            match = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if match:
                new_line = int(match.group(1)) - 1
            continue
        if line.startswith("+") and not line.startswith("+++"):
            new_line += 1
            content = line[1:]
            match = _TRAILING.search(content)
            if match and match.group(0) != "  ":
                escaped = match.group(0).replace("\t", "\\t").replace(" ", "·")
                failures.append(
                    f"{current_file}:{new_line}: invalid trailing whitespace ({escaped})"
                )
            continue
        if line.startswith(" "):
            new_line += 1

    return failures


def main() -> int:
    failures = violations(sys.stdin.readlines())
    if not failures:
        return 0
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
