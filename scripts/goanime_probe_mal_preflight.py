#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any


def _write_outputs(*, category: str, error_count: int, entry_count: int) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as output:
        output.write(f"category={category}\n")
        output.write(f"error_count={error_count}\n")
        output.write(f"entry_count={entry_count}\n")


def _classify(raw: Any) -> tuple[str, int, int]:
    if not isinstance(raw, dict):
        return "container", 1, 0
    if raw.get("schemaVersion") != 1:
        return "schema", 1, 0
    generated_at = raw.get("generatedAt")
    if not isinstance(generated_at, str) or not generated_at.strip():
        return "generated-at", 1, 0
    entries = raw.get("entries")
    if not isinstance(entries, list):
        return "entries-container", 1, 0

    seen_ids: set[int] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            return "entry-object", 1, len(entries)
        mal_id = entry.get("malId")
        if type(mal_id) is not int or mal_id <= 0 or mal_id in seen_ids:
            return "mal-id", 1, len(entries)
        seen_ids.add(mal_id)
        canonical = entry.get("canonicalTitle")
        if not isinstance(canonical, str) or not canonical.strip():
            return "canonical-title", 1, len(entries)
        matched = entry.get("matchedAvailableTitles")
        if not isinstance(matched, list) or any(
            not isinstance(title, str) or not title.strip() for title in matched
        ):
            return "matched-titles", 1, len(entries)
        modes = entry.get("modes")
        if not isinstance(modes, dict):
            return "modes-object", 1, len(entries)
        if not isinstance(modes.get("sub"), bool):
            return "modes-sub", 1, len(entries)
        if not isinstance(modes.get("dub"), bool):
            return "modes-dub", 1, len(entries)
    return "ok", 0, len(entries)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()

    path = args.repo_root.resolve() / "assets" / "data" / "mal_availability_map.json"
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        category, error_count, entry_count = "missing", 1, 0
    except (OSError, UnicodeError):
        category, error_count, entry_count = "read-error", 1, 0
    except json.JSONDecodeError:
        category, error_count, entry_count = "json", 1, 0
    else:
        category, error_count, entry_count = _classify(raw)

    _write_outputs(
        category=category,
        error_count=error_count,
        entry_count=entry_count,
    )
    print(f"MAL preflight structural category: {category}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
