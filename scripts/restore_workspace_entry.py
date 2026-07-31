#!/usr/bin/env python3
"""Official restore entrypoint with post-restore project-cache preparation."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.lib.artifact_contract import safe_relative_path
from scripts.native_asset_cache import prepare_project_cache


def prepare_restored_project_caches(destination: Path) -> list[dict[str, Any]]:
    destination = destination.resolve()
    if not (destination / "pubspec.yaml").is_file():
        raise ValueError(f"restored project pubspec.yaml not found: {destination}")
    toolchains = destination.parent / f".{destination.name}-toolchains"
    if not toolchains.is_dir():
        raise ValueError(f"restored toolchains directory not found: {toolchains}")

    prepared: list[dict[str, Any]] = []
    for manifest_path in sorted(toolchains.glob("*/.artifact-set.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        relative = manifest.get("project_cache")
        if relative is None:
            continue
        if not isinstance(relative, str) or not safe_relative_path(relative):
            raise ValueError(f"unsafe project cache path in {manifest_path}")
        root = manifest_path.parent.resolve()
        cache = (root / relative).resolve()
        cache.relative_to(root)
        result = prepare_project_cache(cache, destination)
        prepared.append({"profile": str(manifest.get("profile", "unknown")), **result})
    return prepared


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--project", required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    return parser


def main() -> int:
    args, _ = _parser().parse_known_args()
    core = Path(__file__).with_name("restore_workspace.py")
    completed = subprocess.run(
        [sys.executable, str(core), *sys.argv[1:]],
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        sys.stdout.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        return completed.returncode

    try:
        report = json.loads(completed.stdout)
        report["prepared_project_caches"] = prepare_restored_project_caches(args.destination)
        report_path = args.report.resolve() if args.report else args.destination.resolve().parent / f"{args.project}-restore-report.json"
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"workspace cache preparation failed: {error}", file=sys.stderr)
        return 2

    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
