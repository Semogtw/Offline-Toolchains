#!/usr/bin/env python3
"""Compute the exact schema-v2 artifact-set fingerprint before packaging."""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.lib.artifact_contract import canonical_json_bytes, compute_fingerprint
from scripts.lib.profile_registry import load_profiles


def builder_fingerprint(profile: dict, repository_root: Path) -> str:
    return compute_fingerprint([
        canonical_json_bytes(profile),
        (repository_root / "scripts/build_artifact_set.py").read_bytes(),
        (repository_root / "scripts/doctor.py").read_bytes(),
        (repository_root / "scripts/lib/artifact_contract.py").read_bytes(),
    ])


def set_fingerprint(profile_name: str, package: str, lock_mode: str, lock_fingerprint: str, workflow_commit: str, repository_root: Path) -> dict[str, str]:
    profile = load_profiles(repository_root / "profiles")[profile_name]
    builder = builder_fingerprint(profile, repository_root)
    complete = compute_fingerprint([
        profile_name.encode(), package.encode(), lock_mode.encode(),
        lock_fingerprint.encode(), builder.encode(), workflow_commit.encode(),
    ])
    return {"builder_fingerprint": builder, "set_fingerprint": complete, "fingerprint_prefix": complete[:16]}


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument('--profile',required=True)
    parser.add_argument('--package',required=True)
    parser.add_argument('--lock-mode',required=True)
    parser.add_argument('--lock-fingerprint',required=True)
    parser.add_argument('--workflow-commit',required=True)
    parser.add_argument('--repository-root',type=Path,default=Path(__file__).resolve().parents[1])
    args=parser.parse_args()
    try:
        result=set_fingerprint(args.profile,args.package,args.lock_mode,args.lock_fingerprint,args.workflow_commit,args.repository_root.resolve())
    except (OSError,ValueError,KeyError) as error:
        print(f'artifact fingerprint failed: {error}',file=sys.stderr); return 2
    print(json.dumps(result,sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
