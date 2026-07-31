#!/usr/bin/env python3
"""Artifact catalog, reuse and conservative cleanup selection."""
from __future__ import annotations
import argparse
import datetime as dt
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

NAME_RE = re.compile(r"^(?P<profile>[a-z0-9][a-z0-9._-]*)-(?P<fp>[0-9a-f]{16})-(?P<run>[0-9]+)-(?P<role>manifest|part-[0-9]{2})$")
PROTECTED_PREFIXES = ("private-source-", "offline-toolchains-workspace", "toolchain-receipt-")

@dataclass
class Group:
    profile: str
    fingerprint_prefix: str
    run_id: int
    artifacts: list[dict[str, Any]]

    @property
    def key(self) -> tuple[str, str, int]:
        return (self.profile, self.fingerprint_prefix, self.run_id)

    @property
    def manifest_artifacts(self) -> list[dict[str, Any]]:
        return [item for item in self.artifacts if item["name"].endswith("-manifest")]

    @property
    def part_artifacts(self) -> list[dict[str, Any]]:
        return [item for item in self.artifacts if "-part-" in item["name"]]


def load_artifacts(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    items = data.get("artifacts", data) if isinstance(data, dict) else data
    if not isinstance(items, list):
        raise ValueError("artifacts JSON must contain a list")
    return items


def groups(artifacts: list[dict[str, Any]]) -> dict[tuple[str, str, int], Group]:
    result: dict[tuple[str, str, int], Group] = {}
    for artifact in artifacts:
        name = str(artifact.get("name", ""))
        if name.startswith(PROTECTED_PREFIXES):
            continue
        match = NAME_RE.fullmatch(name)
        if not match:
            continue
        key = (match["profile"], match["fp"], int(match["run"]))
        result.setdefault(key, Group(*key, [])).artifacts.append(artifact)
    return result


def _unexpired(artifact: dict[str, Any]) -> bool:
    return not bool(artifact.get("expired"))


def candidate_manifests(artifacts: list[dict[str, Any]], profile: str, set_fingerprint: str) -> list[dict[str, Any]]:
    prefix = set_fingerprint[:16]
    candidates: list[dict[str, Any]] = []
    for group in groups(artifacts).values():
        if group.profile == profile and group.fingerprint_prefix == prefix:
            candidates.extend(item for item in group.manifest_artifacts if _unexpired(item))
    return sorted(candidates, key=lambda item: (item.get("created_at", ""), item.get("id", 0)), reverse=True)


def verify_reusable(manifest: dict[str, Any], artifacts: list[dict[str, Any]]) -> dict[str, Any] | None:
    if manifest.get("set_fingerprint", "")[:16] not in manifest.get("artifact_set_id", ""):
        return None
    expected_names = [f"{manifest['artifact_set_id']}-manifest", *[part["artifact_name"] for part in manifest["parts"]]]
    by_name = {item.get("name"): item for item in artifacts if _unexpired(item)}
    if any(name not in by_name for name in expected_names):
        return None
    selected = [by_name[name] for name in expected_names]
    if any(int(item.get("workflow_run", {}).get("id", manifest["run_id"])) != int(manifest["run_id"]) for item in selected):
        return None
    return {
        "artifact_set_id": manifest["artifact_set_id"],
        "profile": manifest["profile"],
        "set_fingerprint": manifest["set_fingerprint"],
        "artifact_ids": [item["id"] for item in selected],
        "artifacts": selected,
    }


def parse_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(dt.timezone.utc)


def select_cleanup(artifacts: list[dict[str, Any]], current_manifests: list[dict[str, Any]], now: dt.datetime) -> list[dict[str, Any]]:
    grouped = groups(artifacts)
    delete: dict[int, dict[str, Any]] = {}
    current_keys = {(item["profile"], item["set_fingerprint"][:16], int(item["run_id"])) for item in current_manifests}
    current_pairs = {(item["profile"], item["set_fingerprint"][:16]) for item in current_manifests}
    for group in grouped.values():
        if group.key in current_keys:
            continue
        if (group.profile, group.fingerprint_prefix) in current_pairs:
            for artifact in group.artifacts:
                delete[int(artifact["id"])] = artifact
            continue
        complete = bool(group.manifest_artifacts and group.part_artifacts)
        if complete:
            continue
        created_values = [item.get("created_at") for item in group.artifacts if item.get("created_at")]
        if not created_values:
            continue
        oldest = min(parse_time(value) for value in created_values)
        if now - oldest >= dt.timedelta(hours=6):
            for artifact in group.artifacts:
                delete[int(artifact["id"])] = artifact
    return sorted(delete.values(), key=lambda item: int(item["id"]))


def render_catalog(profile: str, run: dict[str, Any], artifacts: list[dict[str, Any]], manifests: list[dict[str, Any]], result: str, deleted: list[dict[str, Any]]) -> str:
    marker = f"<!-- toolchain-profile:{profile} -->"
    lines = [
        marker,
        f"### Toolchain profile `{profile}`",
        "",
        f"- Run: [{run.get('id')}]({run.get('html_url', '')})",
        f"- Conclusion: `{run.get('conclusion', 'unknown')}`",
        f"- Result: `{result}`",
    ]
    for manifest in manifests:
        lines.extend([
            f"- Artifact set: `{manifest['artifact_set_id']}`",
            f"- Lock mode: `{manifest['lock_mode']}`",
            f"- Lock fingerprint: `{manifest['lock_fingerprint']}`",
            f"- Set fingerprint: `{manifest['set_fingerprint']}`",
        ])
    if artifacts:
        lines.append("- Artifacts:")
        for artifact in sorted(artifacts, key=lambda item: item.get("name", "")):
            size = int(artifact.get("size_in_bytes", 0)) / 1024 / 1024
            lines.append(f"  - `{artifact.get('name')}` — ID `{artifact.get('id')}` — {size:.1f} MiB — expires {artifact.get('expires_at', 'unknown')}")
    else:
        lines.append("- Artifacts: none")
    deleted_size = sum(int(item.get("size_in_bytes", 0)) for item in deleted) / 1024 / 1024
    lines.append(f"- Cleanup: {len(deleted)} artifact(s), {deleted_size:.1f} MiB selected")
    return "\n".join(lines)


def build_report_plan(run: dict[str, Any], all_artifacts: list[dict[str, Any]], receipts: list[dict[str, Any]], now: dt.datetime) -> dict[str, Any]:
    comments: list[dict[str, str]] = []
    current_manifests: list[dict[str, Any]] = []
    all_by_id = {int(item["id"]): item for item in all_artifacts if item.get("id") is not None}
    all_by_name = {str(item.get("name")): item for item in all_artifacts if item.get("name")}
    for receipt in receipts:
        manifest = receipt["manifest"]
        current_manifests.append(manifest)
        expected_names = [f"{manifest['artifact_set_id']}-manifest", *[part["artifact_name"] for part in manifest["parts"]]]
        selected: list[dict[str, Any]] = []
        for artifact_id in receipt.get("artifact_ids", []):
            if int(artifact_id) in all_by_id:
                selected.append(all_by_id[int(artifact_id)])
        if not selected:
            selected = [all_by_name[name] for name in expected_names if name in all_by_name]
        comments.append({
            "profile": manifest["profile"],
            "marker": f"<!-- toolchain-profile:{manifest['profile']} -->",
            "body": render_catalog(manifest["profile"], run, selected, [manifest], receipt.get("result", "built"), []),
        })
    deleted = select_cleanup(all_artifacts, current_manifests, now)
    for comment in comments:
        profile = comment["profile"]
        profile_deleted = [item for item in deleted if (match := NAME_RE.fullmatch(str(item.get("name", "")))) and match["profile"] == profile]
        receipt = next(item for item in receipts if item["manifest"]["profile"] == profile)
        manifest = receipt["manifest"]
        expected_names = [f"{manifest['artifact_set_id']}-manifest", *[part["artifact_name"] for part in manifest["parts"]]]
        selected = [all_by_name[name] for name in expected_names if name in all_by_name]
        if receipt.get("artifact_ids"):
            selected = [all_by_id[int(item)] for item in receipt["artifact_ids"] if int(item) in all_by_id]
        comment["body"] = render_catalog(profile, run, selected, [manifest], receipt.get("result", "built"), profile_deleted)
    return {"comments": comments, "delete_artifact_ids": [int(item["id"]) for item in deleted]}


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    command = sub.add_parser("candidate-manifests")
    command.add_argument("--artifacts-json", type=Path, required=True)
    command.add_argument("--profile", required=True)
    command.add_argument("--set-fingerprint", required=True)
    command = sub.add_parser("verify-reusable")
    command.add_argument("--artifacts-json", type=Path, required=True)
    command.add_argument("--manifest", type=Path, required=True)
    command = sub.add_parser("select-cleanup")
    command.add_argument("--artifacts-json", type=Path, required=True)
    command.add_argument("--current-manifest", type=Path, action="append", default=[])
    command.add_argument("--now")
    command = sub.add_parser("report-plan")
    command.add_argument("--run-json", type=Path, required=True)
    command.add_argument("--artifacts-json", type=Path, required=True)
    command.add_argument("--receipts-dir", type=Path, required=True)
    command.add_argument("--now")
    args = parser.parse_args()
    try:
        artifacts = load_artifacts(args.artifacts_json)
        if args.command == "candidate-manifests":
            result = candidate_manifests(artifacts, args.profile, args.set_fingerprint)
        elif args.command == "verify-reusable":
            result = verify_reusable(json.loads(args.manifest.read_text(encoding="utf-8")), artifacts)
        elif args.command == "select-cleanup":
            manifests = [json.loads(path.read_text(encoding="utf-8")) for path in args.current_manifest]
            now = parse_time(args.now) if args.now else dt.datetime.now(dt.timezone.utc)
            result = select_cleanup(artifacts, manifests, now)
        else:
            run = json.loads(args.run_json.read_text(encoding="utf-8"))
            receipts = [json.loads(path.read_text(encoding="utf-8")) for path in sorted(args.receipts_dir.rglob("receipt.json"))]
            if not receipts:
                raise ValueError("no toolchain receipts found")
            now = parse_time(args.now) if args.now else dt.datetime.now(dt.timezone.utc)
            result = build_report_plan(run, artifacts, receipts, now)
        print(json.dumps(result, sort_keys=True))
    except (OSError, ValueError, json.JSONDecodeError, KeyError) as error:
        print(f"artifact catalog failed: {error}", file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
