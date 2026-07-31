#!/usr/bin/env python3
"""Run schema-v2 toolchain health checks."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

try:
    from scripts.lib.artifact_contract import load_and_validate_manifest, safe_relative_path
except ModuleNotFoundError:
    # Packaged artifacts carry the contract validator next to this script.
    from artifact_contract import load_and_validate_manifest, safe_relative_path


def _resolve(root: Path, relative: str) -> Path:
    if not safe_relative_path(relative):
        raise ValueError(f"unsafe check path: {relative}")
    result = (root / relative).resolve()
    result.relative_to(root.resolve())
    return result


def run_checks(manifest: dict[str, Any], root: Path) -> dict[str, Any]:
    checks = manifest.get("doctor_checks", [])
    results: list[dict[str, Any]] = []
    missing = 0
    incompatible = 0

    for index, check in enumerate(checks):
        result: dict[str, Any] = {"index": index, "type": check.get("type"), "ok": False}
        try:
            check_type = check.get("type")
            if check_type in {"executable", "directory", "file"}:
                path = _resolve(root, str(check.get("path", "")))
                result["path"] = str(path)
                if check_type == "executable":
                    result["ok"] = path.is_file() and os.access(path, os.X_OK)
                elif check_type == "directory":
                    result["ok"] = path.is_dir()
                else:
                    result["ok"] = path.is_file()
                if not result["ok"]:
                    missing += 1
                    result["error"] = f"missing {check_type}: {check.get('path')}"
            elif check_type == "version_contains":
                command = check.get("command")
                needle = check.get("contains")
                if not isinstance(command, list) or not command or not isinstance(needle, str):
                    raise ValueError("version_contains requires command and contains")
                resolved_command = [str(_resolve(root, command[0])), *map(str, command[1:])]
                completed = subprocess.run(resolved_command, cwd=root, text=True, capture_output=True, timeout=30)
                output = (completed.stdout + completed.stderr).strip()
                result.update(command=resolved_command, output=output, returncode=completed.returncode)
                result["ok"] = completed.returncode == 0 and needle in output
                if not result["ok"]:
                    incompatible += 1
                    result["error"] = f"version output does not contain {needle!r}"
            elif check_type == "environment":
                name = check.get("name")
                expected = check.get("equals")
                actual = os.environ.get(str(name))
                result.update(name=name, actual=actual)
                result["ok"] = actual == expected
                if not result["ok"]:
                    incompatible += 1
                    result["error"] = f"environment {name} mismatch"
            elif check_type == "command_optional":
                command = check.get("command")
                if not isinstance(command, list) or not command:
                    raise ValueError("command_optional requires command")
                completed = subprocess.run(list(map(str, command)), cwd=root, text=True, capture_output=True, timeout=120)
                result.update(command=command, output=(completed.stdout + completed.stderr).strip(), returncode=completed.returncode)
                result["ok"] = completed.returncode == 0
                if not result["ok"]:
                    missing += 1
                    result["error"] = "optional command failed"
            else:
                raise ValueError(f"unsupported doctor check: {check_type}")
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            result["error"] = str(error)
            incompatible += 1
        results.append(result)

    if incompatible:
        status = "incompatible"
    elif missing:
        status = "partial"
    else:
        status = "ready"
    return {
        "status": status,
        "profile": manifest["profile"],
        "package": manifest["package"],
        "artifact_set_id": manifest["artifact_set_id"],
        "lock_mode": manifest["lock_mode"],
        "lock_fingerprint": manifest["lock_fingerprint"],
        "checks": results,
        "errors": [item["error"] for item in results if "error" in item],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        manifest = load_and_validate_manifest(args.manifest)
        root = (args.root or args.manifest.parent).resolve()
        result = run_checks(manifest, root)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        result = {"status": "incompatible", "errors": [str(error)], "checks": []}
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"{result['status']}: {result.get('profile', 'unknown')}/{result.get('package', 'unknown')}")
        for check in result.get("checks", []):
            marker = "PASS" if check.get("ok") else "FAIL"
            print(f"[{marker}] {check.get('type')}: {check.get('path') or check.get('command') or check.get('name')}")
        for error in result.get("errors", []):
            print(f"error: {error}", file=sys.stderr)
    return 0 if result["status"] == "ready" else 1


if __name__ == "__main__":
    raise SystemExit(main())
