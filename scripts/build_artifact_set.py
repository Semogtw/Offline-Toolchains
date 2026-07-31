#!/usr/bin/env python3
"""Create a schema-v2 split artifact set from one portable package root."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from typing import Any

from scripts.lib.artifact_contract import SCHEMA_VERSION, canonical_json_bytes, compute_fingerprint, sha256_file, validate_manifest
from scripts.lib.profile_registry import load_profiles
from scripts.artifact_fingerprint import builder_fingerprint as compute_builder_fingerprint, set_fingerprint as compute_set_fingerprint

DEFAULT_PART_SIZE = 400 * 1024 * 1024


def _utc(value: str | None, *, default_offset_days: int = 0) -> str:
    if value:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        parsed = dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=default_offset_days)
    return parsed.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _spdx(software: list[dict[str, Any]], namespace: str, created_at: str) -> dict[str, Any]:
    packages = []
    relationships = []
    for index, item in enumerate(software, start=1):
        spdx_id = f"SPDXRef-Package-{index}"
        packages.append({
            "SPDXID": spdx_id,
            "name": str(item.get("name", f"package-{index}")),
            "versionInfo": str(item.get("version", "unknown")),
            "downloadLocation": str(item.get("source", "NOASSERTION")),
            "licenseConcluded": str(item.get("license", "NOASSERTION")),
            "licenseDeclared": str(item.get("license", "NOASSERTION")),
            "filesAnalyzed": False,
        })
        relationships.append({"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": spdx_id})
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": namespace,
        "documentNamespace": f"https://github.com/Semogtw/Offline-Toolchains/spdx/{namespace}",
        "creationInfo": {"created": created_at, "creators": ["Tool: Offline-Toolchains/build_artifact_set.py"]},
        "packages": packages,
        "relationships": relationships,
    }


def package(args: argparse.Namespace) -> dict[str, Any]:
    root = args.root.resolve()
    out = args.out.resolve()
    if not root.is_dir():
        raise ValueError(f"package root not found: {root}")
    registry = load_profiles(args.profiles.resolve())
    if args.profile not in registry:
        raise ValueError(f"unknown profile: {args.profile}")
    profile = registry[args.profile]
    if profile["kind"] != "concrete" or profile["packages"] != [args.package]:
        raise ValueError("profile/package mismatch")
    out.mkdir(parents=True, exist_ok=True)

    created_at = _utc(args.created_at)
    expires_at = _utc(args.expires_at, default_offset_days=1)
    software = json.loads(args.software.read_text(encoding="utf-8")) if args.software else []
    if not isinstance(software, list):
        raise ValueError("software inventory input must be a list")

    shutil.copy2(Path(__file__).with_name("doctor.py"), root / "doctor.py")
    shutil.copy2(Path(__file__).parent / "lib" / "artifact_contract.py", root / "artifact_contract.py")
    shutil.copy2(Path(__file__).with_name("doctor.sh"), root / "doctor.sh")
    os.chmod(root / "doctor.sh", 0o755)
    project_cache_relative = "native-assets-cache/hooks_runner-shared"
    project_cache = root / project_cache_relative
    has_project_cache = project_cache.is_dir() and any(path.is_file() for path in project_cache.rglob("*"))
    if has_project_cache:
        shutil.copy2(Path(__file__).with_name("native_asset_cache.py"), root / "native_asset_cache.py")
        shutil.copy2(Path(__file__).with_name("prepare-project.sh"), root / "prepare-project.sh")
        os.chmod(root / "native_asset_cache.py", 0o755)
        os.chmod(root / "prepare-project.sh", 0o755)
    (root / "profile.json").write_text(json.dumps(profile, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    calculated = compute_set_fingerprint(
        args.profile, args.package, args.lock_mode, args.lock_fingerprint,
        args.workflow_commit, Path(__file__).resolve().parents[1],
    )
    builder_fingerprint = args.builder_fingerprint or calculated["builder_fingerprint"]
    if args.builder_fingerprint:
        set_fingerprint = compute_fingerprint([
            args.profile.encode(), args.package.encode(), args.lock_mode.encode(),
            args.lock_fingerprint.encode(), builder_fingerprint.encode(), args.workflow_commit.encode(),
        ])
    else:
        set_fingerprint = calculated["set_fingerprint"]
    prefix = set_fingerprint[:16]
    artifact_set_id = f"{args.profile}-{prefix}-{args.run_id}"
    archive_name = args.archive_name or f"{args.package}.tar.zst"
    archive = out / archive_name

    sbom = _spdx(software, artifact_set_id, created_at)
    (root / "SBOM.spdx.json").write_text(json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    env = os.environ.copy()
    subprocess.run([
        "tar", "-C", str(root.parent), "-I", "zstd -T0 -8", "-cf", str(archive), root.name
    ], check=True, env=env)

    part_size = args.part_size
    parts: list[dict[str, Any]] = []
    with archive.open("rb") as source:
        index = 0
        while True:
            chunk = source.read(part_size)
            if not chunk:
                break
            part_name = f"{archive_name}.part-{index:02d}"
            part_path = out / part_name
            part_path.write_bytes(chunk)
            artifact_name = f"{artifact_set_id}-part-{index:02d}"
            parts.append({
                "index": index,
                "name": part_name,
                "artifact_name": artifact_name,
                "sha256": sha256_file(part_path),
                "size": part_path.stat().st_size,
            })
            index += 1
    if not parts:
        raise ValueError("archive produced no parts")

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "artifact_set_id": artifact_set_id,
        "set_fingerprint": set_fingerprint,
        "profile": args.profile,
        "package": args.package,
        "lock_mode": args.lock_mode,
        "lock_fingerprint": args.lock_fingerprint,
        "builder_fingerprint": builder_fingerprint,
        "workflow": args.workflow,
        "workflow_commit": args.workflow_commit,
        "run_id": args.run_id,
        "created_at": created_at,
        "expires_at": expires_at,
        "platform": "linux",
        "architecture": "x86_64",
        "archive": {"name": archive_name, "sha256": sha256_file(archive), "size": archive.stat().st_size},
        "parts": parts,
        "requires": profile["requires"],
        "activation_script": "activate.sh",
        "doctor_script": "doctor.sh",
        "doctor_checks": profile["doctor_checks"],
        "software_inventory": "SBOM.spdx.json",
        "compatibility": {"minimum_restore_version": 2, "exact_lock_required": args.lock_mode == "private-exact"},
        **({
            "project_cache": project_cache_relative,
            "project_prepare_script": "prepare-project.sh",
        } if has_project_cache else {}),
    }
    errors = validate_manifest(manifest)
    if errors:
        raise ValueError("generated invalid manifest: " + "; ".join(errors))
    (out / "artifact-set.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    shutil.copy2(root / "SBOM.spdx.json", out / "SBOM.spdx.json")
    (out / "SHA256SUMS.parts").write_text("".join(f"{part['sha256']}  {part['name']}\n" for part in parts), encoding="utf-8")
    (out / "PARTS.txt").write_text(
        f"artifact_set_id={artifact_set_id}\narchive={archive_name}\narchive_sha256={manifest['archive']['sha256']}\npart_size={part_size}\n"
        + "".join(f"part={part['name']} size={part['size']} sha256={part['sha256']}\n" for part in parts),
        encoding="utf-8",
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--profiles", type=Path, default=Path("profiles"))
    parser.add_argument("--lock-mode", required=True, choices=["synthetic", "private-exact", "not-applicable"])
    parser.add_argument("--lock-fingerprint", required=True)
    parser.add_argument("--builder-fingerprint")
    parser.add_argument("--workflow", required=True)
    parser.add_argument("--workflow-commit", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--created-at")
    parser.add_argument("--expires-at")
    parser.add_argument("--software", type=Path)
    parser.add_argument("--archive-name")
    parser.add_argument("--part-size", type=int, default=DEFAULT_PART_SIZE)
    args = parser.parse_args()
    try:
        manifest = package(args)
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"artifact packaging failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
