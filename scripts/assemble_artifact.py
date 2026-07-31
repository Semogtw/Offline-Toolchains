#!/usr/bin/env python3
"""Safely collect connector ZIPs and assemble one schema-v2 archive."""

from __future__ import annotations

import argparse
import json
import shutil
import stat
import tempfile
import zipfile
import sys
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.lib.artifact_contract import load_and_validate_manifest, safe_relative_path, sha256_file


def safe_extract_zip(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as handle:
        for info in handle.infolist():
            name = info.filename.rstrip("/")
            if not name:
                continue
            if not safe_relative_path(name):
                raise ValueError(f"unsafe ZIP member: {info.filename}")
            mode = (info.external_attr >> 16) & 0o170000
            if mode == stat.S_IFLNK:
                raise ValueError(f"ZIP symlink is not allowed: {info.filename}")
            target = (destination / name).resolve()
            target.relative_to(destination.resolve())
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with handle.open(info) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)


def collect(downloads: Path, destination: Path) -> None:
    for archive in sorted(downloads.rglob("*.zip")):
        safe_extract_zip(archive, destination)
    for path in sorted(downloads.rglob("*")):
        if path.is_file() and path.suffix != ".zip":
            target = destination / path.name
            if target.exists() and sha256_file(target) != sha256_file(path):
                raise ValueError(f"conflicting duplicate file: {path.name}")
            shutil.copy2(path, target)


def find_manifest(collected: Path, artifact_set_id: str | None) -> Path:
    manifests = list(collected.rglob("artifact-set.json"))
    if artifact_set_id:
        manifests = [path for path in manifests if json.loads(path.read_text(encoding="utf-8")).get("artifact_set_id") == artifact_set_id]
    if len(manifests) != 1:
        raise ValueError(f"expected exactly one matching manifest, found {len(manifests)}")
    return manifests[0]


def assemble(downloads: Path, output: Path, artifact_set_id: str | None = None) -> dict:
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    with tempfile.TemporaryDirectory(prefix="offline-artifact-") as directory:
        collected = Path(directory)
        collect(downloads, collected)
        manifest = load_and_validate_manifest(find_manifest(collected, artifact_set_id))
        with output.open("wb") as stream:
            for part in manifest["parts"]:
                path = collected / part["name"]
                if not path.is_file():
                    raise ValueError(f"missing part: {part['name']}")
                if path.stat().st_size != part["size"]:
                    raise ValueError(f"part size mismatch: {part['name']}")
                if sha256_file(path) != part["sha256"]:
                    raise ValueError(f"part checksum mismatch: {part['name']}")
                with path.open("rb") as source:
                    shutil.copyfileobj(source, stream)
        if output.stat().st_size != manifest["archive"]["size"] or sha256_file(output) != manifest["archive"]["sha256"]:
            output.unlink(missing_ok=True)
            raise ValueError("assembled archive checksum or size mismatch")
        return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("downloads", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--artifact-set-id")
    args = parser.parse_args()
    try:
        manifest = assemble(args.downloads.resolve(), args.output.resolve(), args.artifact_set_id)
    except (OSError, ValueError, json.JSONDecodeError, zipfile.BadZipFile) as error:
        print(f"artifact assembly failed: {error}")
        return 2
    print(json.dumps({"output": str(args.output), "artifact_set_id": manifest["artifact_set_id"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
