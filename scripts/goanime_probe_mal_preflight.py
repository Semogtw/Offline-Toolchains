#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _category(errors: list[str]) -> str:
    if not errors:
        return "ok"
    first = errors[0].lower()
    if "missing or incompatible" in first or "schemaversion" in first:
        return "schema"
    if "generatedat" in first:
        return "generated-at"
    if "entries must be a list" in first:
        return "entries-container"
    if "entry must be an object" in first:
        return "entry-object"
    if "malid" in first:
        return "mal-id"
    if "canonicaltitle" in first:
        return "canonical-title"
    if "matchedavailabletitles" in first:
        return "matched-titles"
    if "modes.sub" in first:
        return "modes-sub"
    if "modes.dub" in first:
        return "modes-dub"
    if "modes must be an object" in first:
        return "modes-object"
    return "other"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    tooling = repo / "tools" / "scrapling_provider_pipeline"
    sys.path.insert(0, str(tooling))

    from cache_contract import load_json  # noqa: PLC0415
    from mal_input_preflight import validate_mal_availability_input  # noqa: PLC0415

    raw = load_json(repo / "assets" / "data" / "mal_availability_map.json")
    errors = validate_mal_availability_input(raw)
    category = _category(errors)

    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write(f"category={category}\n")
            output.write(f"error_count={len(errors)}\n")

    if errors:
        # Intentionally do not print raw validation errors; they may contain
        # source indices or identifiers. The category is sufficient to route
        # the repair while keeping diagnostics public-safe.
        print(f"MAL preflight category: {category}", file=sys.stderr)
        return 1

    print("MAL preflight category: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
