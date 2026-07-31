#!/usr/bin/env python3
"""Rewrite Flutter tool package metadata so a copied SDK remains relocatable."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from urllib.parse import quote, unquote, urljoin, urlparse


def _file_uri_path(value: str, *, field: str) -> Path:
    parsed = urlparse(value)
    if parsed.scheme != "file" or parsed.netloc not in {"", "localhost"}:
        raise ValueError(f"{field} must be a local file URI")
    return Path(unquote(parsed.path)).resolve()


def _relative_uri(target: Path, base: Path) -> str:
    relative = os.path.relpath(target.resolve(), base.resolve()).replace(os.sep, "/")
    return quote(relative, safe="/@:+")


def _resolve_relative_uri(value: str, config: Path) -> Path:
    parsed = urlparse(urljoin(config.resolve().as_uri(), value))
    if parsed.scheme != "file" or parsed.netloc not in {"", "localhost"}:
        raise ValueError(f"relocated URI is not local: {value}")
    return Path(unquote(parsed.path)).resolve()


def relocate_flutter_sdk(flutter_root: Path, pub_cache: Path) -> dict[str, int | str]:
    flutter_root = flutter_root.resolve()
    pub_cache = pub_cache.resolve()
    config = flutter_root / "packages" / "flutter_tools" / ".dart_tool" / "package_config.json"
    if not flutter_root.is_dir():
        raise ValueError(f"Flutter root not found: {flutter_root}")
    if not pub_cache.is_dir():
        raise ValueError(f"Pub cache not found: {pub_cache}")
    if not config.is_file():
        raise ValueError(f"Flutter tool package config not found: {config}")

    data = json.loads(config.read_text(encoding="utf-8"))
    packages = data.get("packages")
    if not isinstance(packages, list) or not packages:
        raise ValueError("Flutter tool package config has no packages")
    source_pub_cache_value = data.get("pubCache")
    if not isinstance(source_pub_cache_value, str):
        raise ValueError("Flutter tool package config has no pubCache URI")
    source_pub_cache = _file_uri_path(source_pub_cache_value, field="pubCache")

    relocated = 0
    for package in packages:
        if not isinstance(package, dict) or not isinstance(package.get("rootUri"), str):
            raise ValueError("Flutter tool package entry has no rootUri")
        root_uri = package["rootUri"]
        parsed = urlparse(root_uri)
        if parsed.scheme == "file":
            source_root = _file_uri_path(root_uri, field=f"rootUri for {package.get('name', 'unknown')}")
            try:
                cache_relative = source_root.relative_to(source_pub_cache)
            except ValueError as error:
                raise ValueError(
                    f"absolute package root is outside the source Pub cache: {source_root}"
                ) from error
            target_root = pub_cache / cache_relative
            if not (target_root / "pubspec.yaml").is_file():
                raise ValueError(f"relocated package is missing pubspec.yaml: {target_root}")
            package["rootUri"] = _relative_uri(target_root, config.parent)
            relocated += 1
        elif parsed.scheme:
            raise ValueError(f"unsupported package root URI scheme: {root_uri}")

    data["flutterRoot"] = _relative_uri(flutter_root, config.parent)
    data["pubCache"] = _relative_uri(pub_cache, config.parent)

    rendered = json.dumps(data, indent=2, sort_keys=False) + "\n"
    temporary = config.with_suffix(".json.tmp")
    temporary.write_text(rendered, encoding="utf-8")
    temporary.replace(config)

    for package in packages:
        target_root = _resolve_relative_uri(str(package["rootUri"]), config)
        if not (target_root / "pubspec.yaml").is_file():
            raise ValueError(f"rewritten package root is invalid: {target_root}")
    if _resolve_relative_uri(str(data["flutterRoot"]), config) != flutter_root:
        raise ValueError("rewritten flutterRoot does not resolve to the copied SDK")
    if _resolve_relative_uri(str(data["pubCache"]), config) != pub_cache:
        raise ValueError("rewritten pubCache does not resolve to the copied cache")

    return {
        "packages": len(packages),
        "relocated_absolute_packages": relocated,
        "config": str(config),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flutter-root", type=Path, required=True)
    parser.add_argument("--pub-cache", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = relocate_flutter_sdk(args.flutter_root, args.pub_cache)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Flutter SDK relocation failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
