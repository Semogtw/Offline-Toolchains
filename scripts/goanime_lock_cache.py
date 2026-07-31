#!/usr/bin/env python3
"""Build and verify a public hosted-package cache manifest for GoAnime."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PACKAGE_RE = re.compile(r"^[a-z_][a-z0-9_]*$")
VERSION_RE = re.compile(r"^[0-9A-Za-z][0-9A-Za-z.+-]*$")


def parse_lockfile(path: Path) -> dict[str, str]:
    packages: dict[str, dict[str, str]] = {}
    current: str | None = None
    in_packages = False

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if raw_line == "packages:":
            in_packages = True
            current = None
            continue
        if in_packages and raw_line and not raw_line.startswith(" "):
            break
        if not in_packages:
            continue
        package_match = re.fullmatch(r"  ([a-z_][a-z0-9_]*):", raw_line)
        if package_match:
            current = package_match.group(1)
            packages[current] = {}
            continue
        if current is None:
            continue
        source_match = re.fullmatch(r"    source: ([A-Za-z0-9_-]+)", raw_line)
        if source_match:
            packages[current]["source"] = source_match.group(1)
            continue
        version_match = re.fullmatch(r'    version: "([^"]+)"', raw_line)
        if version_match:
            packages[current]["version"] = version_match.group(1)

    hosted: dict[str, str] = {}
    for name, metadata in sorted(packages.items()):
        if metadata.get("source") != "hosted":
            continue
        version = metadata.get("version")
        if version is None:
            raise ValueError(f"hosted package {name!r} has no version")
        validate_package(name, version)
        hosted[name] = version
    if not hosted:
        raise ValueError("lockfile contains no hosted packages")
    return hosted


def validate_package(name: str, version: str) -> None:
    if not PACKAGE_RE.fullmatch(name):
        raise ValueError(f"invalid package name: {name!r}")
    if not VERSION_RE.fullmatch(version):
        raise ValueError(f"invalid package version for {name}: {version!r}")


def load_manifest(path: Path) -> dict[str, object]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    packages = data.get("packages")
    if not isinstance(packages, dict) or not packages:
        raise ValueError("packages must be a non-empty object")
    normalized: dict[str, str] = {}
    for raw_name, raw_version in sorted(packages.items()):
        if not isinstance(raw_name, str) or not isinstance(raw_version, str):
            raise ValueError("package names and versions must be strings")
        validate_package(raw_name, raw_version)
        normalized[raw_name] = raw_version
    if data.get("package_count") != len(normalized):
        raise ValueError("package_count does not match packages")
    flutter_version = data.get("flutter_version")
    dart_version = data.get("dart_version")
    if not isinstance(flutter_version, str) or not VERSION_RE.fullmatch(flutter_version):
        raise ValueError("flutter_version is invalid")
    if not isinstance(dart_version, str) or not VERSION_RE.fullmatch(dart_version):
        raise ValueError("dart_version is invalid")
    return {
        "schema_version": 1,
        "flutter_version": flutter_version,
        "dart_version": dart_version,
        "package_count": len(normalized),
        "packages": normalized,
    }


def write_manifest(
    *, lockfile: Path, output: Path, flutter_version: str, dart_version: str
) -> None:
    if not VERSION_RE.fullmatch(flutter_version):
        raise ValueError("flutter_version is invalid")
    if not VERSION_RE.fullmatch(dart_version):
        raise ValueError("dart_version is invalid")
    packages = parse_lockfile(lockfile)
    manifest = {
        "schema_version": 1,
        "flutter_version": flutter_version,
        "dart_version": dart_version,
        "package_count": len(packages),
        "packages": packages,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_pubspec(*, manifest_path: Path, output: Path) -> None:
    manifest = load_manifest(manifest_path)
    packages = manifest["packages"]
    assert isinstance(packages, dict)
    lines = [
        "name: goanime_exact_hosted_cache",
        "description: Exact hosted dependency cache fixture for GoAnime Mobile.",
        "publish_to: none",
        "version: 0.0.0",
        "",
        "environment:",
        '  sdk: ">=3.10.0 <4.0.0"',
        "",
        "dependencies:",
        "  flutter:",
        "    sdk: flutter",
        "  flutter_localizations:",
        "    sdk: flutter",
    ]
    lines.extend(f'  {name}: "{version}"' for name, version in packages.items())
    lines.extend(
        [
            "",
            "dev_dependencies:",
            "  flutter_test:",
            "    sdk: flutter",
            "",
            "flutter:",
            "  uses-material-design: true",
            "",
        ]
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")


def verify_cache(*, manifest_path: Path, pub_cache: Path) -> None:
    manifest = load_manifest(manifest_path)
    packages = manifest["packages"]
    assert isinstance(packages, dict)
    hosted_root = pub_cache / "hosted"
    hosted_dirs = (
        [path for path in hosted_root.iterdir() if path.is_dir()]
        if hosted_root.is_dir()
        else []
    )
    missing = []
    for name, version in packages.items():
        expected = f"{name}-{version}"
        if not any((hosted_dir / expected).is_dir() for hosted_dir in hosted_dirs):
            missing.append(f"{name}={version}")
    if missing:
        raise RuntimeError(
            "GoAnime Pub cache is missing locked hosted packages:\n"
            + "\n".join(missing)
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    extract = subparsers.add_parser("extract-lock")
    extract.add_argument("--lockfile", type=Path, required=True)
    extract.add_argument("--output", type=Path, required=True)
    extract.add_argument("--flutter-version", required=True)
    extract.add_argument("--dart-version", required=True)

    validate = subparsers.add_parser("validate")
    validate.add_argument("--manifest", type=Path, required=True)

    pubspec = subparsers.add_parser("write-pubspec")
    pubspec.add_argument("--manifest", type=Path, required=True)
    pubspec.add_argument("--output", type=Path, required=True)

    verify = subparsers.add_parser("verify-cache")
    verify.add_argument("--manifest", type=Path, required=True)
    verify.add_argument("--pub-cache", type=Path, required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "extract-lock":
            write_manifest(
                lockfile=args.lockfile,
                output=args.output,
                flutter_version=args.flutter_version,
                dart_version=args.dart_version,
            )
        elif args.command == "validate":
            load_manifest(args.manifest)
        elif args.command == "write-pubspec":
            write_pubspec(manifest_path=args.manifest, output=args.output)
        elif args.command == "verify-cache":
            verify_cache(manifest_path=args.manifest, pub_cache=args.pub_cache)
        else:
            raise AssertionError(args.command)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
