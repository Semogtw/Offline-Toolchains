#!/usr/bin/env python3
"""Collect explicit private-project lock inputs and public software inventory."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from pathlib import Path
from typing import Any, Iterable

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.lib.artifact_contract import compute_fingerprint, sha256_file
from scripts.lib.profile_registry import expand_profile, load_profiles

PUB_PACKAGE = re.compile(r"^  ([A-Za-z0-9_.-]+):\s*$")
PUB_FIELD = re.compile(r'^    (source|version):\s*["\']?([^"\']+)["\']?\s*$')
MAVEN_COORD = re.compile(r"[\"']([A-Za-z0-9_.-]+):([A-Za-z0-9_.-]+):([0-9][A-Za-z0-9_.+\-]*)[\"']")


def _matches(root: Path, patterns: Iterable[str]) -> list[Path]:
    result: dict[str, Path] = {}
    root_resolved = root.resolve()
    for pattern in patterns:
        for candidate in root.glob(pattern):
            if candidate.is_dir():
                continue
            if candidate.is_symlink():
                raise ValueError(f"lock input must not be a symlink: {candidate}")
            resolved = candidate.resolve(strict=True)
            resolved.relative_to(root_resolved)
            relative = resolved.relative_to(root_resolved).as_posix()
            result[relative] = resolved
    return [result[name] for name in sorted(result)]


def _pub_inventory(lock: Path) -> list[dict[str, str]]:
    packages: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in lock.read_text(encoding="utf-8").splitlines():
        package = PUB_PACKAGE.match(line)
        if package:
            if current and current.get("source") == "hosted" and current.get("version"):
                packages.append({"name": current["name"], "version": current["version"], "source": "https://pub.dev", "license": "NOASSERTION"})
            current = {"name": package.group(1)}
            continue
        field = PUB_FIELD.match(line)
        if field and current is not None:
            current[field.group(1)] = field.group(2)
    if current and current.get("source") == "hosted" and current.get("version"):
        packages.append({"name": current["name"], "version": current["version"], "source": "https://pub.dev", "license": "NOASSERTION"})
    return packages


def _version_catalog(path: Path) -> list[dict[str, str]]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    versions = {key: str(value) for key, value in data.get("versions", {}).items() if isinstance(value, (str, int, float))}
    packages: list[dict[str, str]] = []
    for section in ("libraries", "plugins"):
        for alias, item in data.get(section, {}).items():
            if not isinstance(item, dict):
                continue
            module = item.get("module") or item.get("id") or alias
            version = item.get("version")
            if isinstance(version, dict):
                version = versions.get(str(version.get("ref")), "unknown")
            elif version is None and "version.ref" in item:
                version = versions.get(str(item["version.ref"]), "unknown")
            packages.append({"name": str(module), "version": str(version or "unknown"), "source": "https://repo.maven.apache.org", "license": "NOASSERTION"})
    return packages


def _cargo_inventory(path: Path) -> list[dict[str, str]]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    result = []
    for package in data.get("package", []):
        if isinstance(package, dict) and package.get("name") and package.get("version"):
            source = str(package.get("source", "https://crates.io"))
            if not source.startswith(("registry+https://github.com/rust-lang/crates.io-index", "https://crates.io")):
                source = "NOASSERTION"
            result.append({"name": str(package["name"]), "version": str(package["version"]), "source": source, "license": "NOASSERTION"})
    return result


def build_inventory(project: str, files: list[Path], root: Path) -> list[dict[str, str]]:
    result: dict[tuple[str, str], dict[str, str]] = {}
    for path in files:
        relative = path.relative_to(root).as_posix()
        items: list[dict[str, str]] = []
        if project == "goanime" and path.name == "pubspec.lock":
            items = _pub_inventory(path)
        elif project == "zapzap" and path.name == "libs.versions.toml":
            items = _version_catalog(path)
        elif project == "zapzap" and path.name == "Cargo.lock":
            items = _cargo_inventory(path)
        elif project == "zapzap" and path.suffix in {".gradle", ".kts"}:
            text = path.read_text(encoding="utf-8", errors="replace")
            items = [
                {"name": f"{group}:{artifact}", "version": version, "source": "https://repo.maven.apache.org", "license": "NOASSERTION"}
                for group, artifact, version in MAVEN_COORD.findall(text)
            ]
        for item in items:
            item["evidence"] = relative
            result[(item["name"], item["version"])] = item
    return [result[key] for key in sorted(result)]


def collect(root: Path, profile_name: str, profiles_root: Path, expected_project: str | None = None) -> dict[str, Any]:
    root = root.resolve()
    registry = load_profiles(profiles_root.resolve())
    if profile_name not in registry:
        raise ValueError(f"unknown profile: {profile_name}")
    concrete = expand_profile(profile_name, registry)
    projects = {registry[name]["project"] for name in concrete if registry[name]["project"]}
    if len(projects) != 1:
        raise ValueError("exact lock collection requires exactly one private project")
    project = next(iter(projects))
    if expected_project and project != expected_project:
        raise ValueError("request project/profile mismatch")
    patterns: list[str] = []
    for name in concrete:
        if registry[name]["project"] == project:
            patterns.extend(registry[name]["lock_inputs"])
    files = _matches(root, patterns)
    if not files:
        raise ValueError("no lock inputs matched")
    entries = []
    fingerprint_parts: list[bytes] = []
    for path in files:
        relative = path.relative_to(root).as_posix()
        digest = sha256_file(path)
        entries.append({"path": relative, "sha256": digest, "size": path.stat().st_size})
        fingerprint_parts.extend([relative.encode("utf-8"), path.read_bytes()])
    fingerprint = compute_fingerprint(fingerprint_parts)
    return {
        "schema_version": 1,
        "profile": profile_name,
        "project": project,
        "lock_fingerprint": fingerprint,
        "files": entries,
        "software": build_inventory(project, files, root),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--profiles", type=Path, default=Path(__file__).resolve().parents[1] / "profiles")
    parser.add_argument("--project", choices=["goanime", "zapzap"])
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    try:
        document = collect(args.root, args.profile, args.profiles, args.project)
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "lock-inputs.json").write_text(json.dumps({key: value for key, value in document.items() if key != "software"}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (args.out / "lock-fingerprint.txt").write_text(document["lock_fingerprint"] + "\n", encoding="utf-8")
        (args.out / "software.json").write_text(json.dumps(document["software"], indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f"lock input collection failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps({key: value for key, value in document.items() if key != "software"}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
