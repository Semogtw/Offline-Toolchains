#!/usr/bin/env python3
"""Restore encrypted private source and compatible schema-v2 toolchains offline."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
import tarfile
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.lib.artifact_contract import load_and_validate_manifest, safe_relative_path, sha256_file
from scripts.lib.profile_registry import expand_profile, load_profiles
from scripts.collect_lock_inputs import collect as collect_lock_inputs

RESTORE_VERSION = 2
EXPECTED_SOURCE_FINGERPRINT = "2DE29DC31427CF0A911AB96175679291435059B0"
PROJECT_REMOTES = {
    "goanime": "https://github.com/Semogtw/goanime-mobile.git",
    "zapzap": "https://github.com/Semogtw/Zapzap.git",
}


@dataclass(frozen=True)
class ZipMember:
    archive: Path
    member: str

    def read_bytes(self) -> bytes:
        with zipfile.ZipFile(self.archive) as handle:
            return handle.read(self.member)


class DownloadIndex:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.members: dict[str, list[ZipMember]] = {}
        self.loose: dict[str, list[Path]] = {}
        self.used_archives: set[Path] = set()
        self._scan()

    def _scan(self) -> None:
        for archive in sorted(self.root.rglob("*.zip")):
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
                    self.members.setdefault(PurePosixPath(name).name, []).append(ZipMember(archive, info.filename))
        for path in sorted(self.root.rglob("*")):
            if path.is_file() and path.suffix != ".zip":
                self.loose.setdefault(path.name, []).append(path)

    def all_named(self, name: str) -> list[ZipMember | Path]:
        return [*self.members.get(name, []), *self.loose.get(name, [])]

    def read_unique(self, name: str) -> bytes:
        candidates = self.all_named(name)
        if len(candidates) != 1:
            raise ValueError(f"expected exactly one {name}, found {len(candidates)}")
        candidate = candidates[0]
        if isinstance(candidate, ZipMember):
            self.used_archives.add(candidate.archive)
            return candidate.read_bytes()
        return candidate.read_bytes()

    def read_matching(self, name: str, expected_sha: str | None = None) -> bytes:
        candidates = self.all_named(name)
        matches: list[tuple[ZipMember | Path, bytes]] = []
        for candidate in candidates:
            data = candidate.read_bytes() if isinstance(candidate, ZipMember) else candidate.read_bytes()
            if expected_sha is None or hashlib.sha256(data).hexdigest() == expected_sha:
                matches.append((candidate, data))
        if len(matches) != 1:
            raise ValueError(f"expected one matching {name}, found {len(matches)}")
        candidate, data = matches[0]
        if isinstance(candidate, ZipMember):
            self.used_archives.add(candidate.archive)
        return data

    def artifact_manifests(self) -> list[tuple[dict[str, Any], ZipMember | Path]]:
        result: list[tuple[dict[str, Any], ZipMember | Path]] = []
        for candidate in self.all_named("artifact-set.json"):
            data = candidate.read_bytes() if isinstance(candidate, ZipMember) else candidate.read_bytes()
            fd, raw_path = tempfile.mkstemp(prefix="artifact-manifest-", suffix=".json")
            os.close(fd)
            path = Path(raw_path)
            try:
                path.write_bytes(data)
                manifest = load_and_validate_manifest(path)
            finally:
                path.unlink(missing_ok=True)
            result.append((manifest, candidate))
        return result

    def mark_used(self, candidate: ZipMember | Path) -> None:
        if isinstance(candidate, ZipMember):
            self.used_archives.add(candidate.archive)


def _run(command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, env=env, check=True, text=True, capture_output=capture)


def _materialize_tar(archive: Path, *, zstd: bool, work: Path) -> Path:
    if not zstd:
        return archive
    output = work / (archive.name[:-4] if archive.name.endswith(".zst") else f"{archive.name}.tar")
    with output.open("wb") as stream:
        subprocess.run(["zstd", "-dc", str(archive)], check=True, stdout=stream)
    return output


def _validate_tar_members(archive: Path, *, zstd: bool = True) -> list[str]:
    with tempfile.TemporaryDirectory(prefix="offline-tar-inspect-") as directory:
        tar_path = _materialize_tar(archive, zstd=zstd, work=Path(directory))
        names: list[str] = []
        with tarfile.open(tar_path, mode="r:") as handle:
            for member in handle.getmembers():
                name = member.name.rstrip("/")
                if name and not safe_relative_path(name):
                    raise ValueError(f"unsafe tar member: {member.name}")
                if member.issym() or member.islnk():
                    link = PurePosixPath(member.linkname)
                    if link.is_absolute() or any(part in {"", ".", ".."} for part in link.parts):
                        raise ValueError(f"unsafe tar link: {member.name} -> {member.linkname}")
                names.append(member.name)
        return names


def safe_extract_tar(archive: Path, destination: Path, *, zstd: bool = True) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="offline-tar-extract-") as directory:
        tar_path = _materialize_tar(archive, zstd=zstd, work=Path(directory))
        with tarfile.open(tar_path, mode="r:") as handle:
            for member in handle.getmembers():
                name = member.name.rstrip("/")
                if name and not safe_relative_path(name):
                    raise ValueError(f"unsafe tar member: {member.name}")
                if member.issym() or member.islnk():
                    link = PurePosixPath(member.linkname)
                    if link.is_absolute() or any(part in {"", ".", ".."} for part in link.parts):
                        raise ValueError(f"unsafe tar link: {member.name} -> {member.linkname}")
            handle.extractall(destination, filter="data")


def _verify_source_transfer(index: DownloadIndex, project: str, work: Path, expected_fingerprint: str = EXPECTED_SOURCE_FINGERPRINT) -> tuple[Path, dict[str, Any]]:
    transfer_candidates = index.all_named("TRANSFER.json")
    if len(transfer_candidates) != 1:
        raise ValueError(f"expected exactly one TRANSFER.json, found {len(transfer_candidates)}")
    transfer_candidate = transfer_candidates[0]

    def companion(name: str) -> bytes:
        if isinstance(transfer_candidate, ZipMember):
            index.used_archives.add(transfer_candidate.archive)
            with zipfile.ZipFile(transfer_candidate.archive) as handle:
                matches = [info.filename for info in handle.infolist() if PurePosixPath(info.filename.rstrip("/")).name == name]
                if len(matches) != 1:
                    raise ValueError(f"source manifest ZIP must contain exactly one {name}")
                return handle.read(matches[0])
        candidate = Path(transfer_candidate).with_name(name)
        if not candidate.is_file():
            raise ValueError(f"source manifest companion missing: {name}")
        return candidate.read_bytes()

    transfer_bytes = transfer_candidate.read_bytes() if isinstance(transfer_candidate, ZipMember) else Path(transfer_candidate).read_bytes()
    transfer = json.loads(transfer_bytes)
    if transfer.get("schema_version") != 1:
        raise ValueError("unsupported source transfer schema")
    if transfer.get("project") != project:
        raise ValueError("source transfer project mismatch")
    if transfer.get("recipient_fingerprint") != expected_fingerprint:
        raise ValueError("source transfer encryption fingerprint mismatch")
    count = transfer.get("part_count")
    if not isinstance(count, int) or not 1 <= count <= 16:
        raise ValueError("invalid source part count")

    checksum_lines = companion("SHA256SUMS.parts").decode("utf-8").splitlines()
    checksums: dict[str, str] = {}
    for line in checksum_lines:
        digest, name = line.split(maxsplit=1)
        checksums[name.strip()] = digest
    encrypted = work / "private-source.gpg"
    with encrypted.open("wb") as stream:
        for number in range(count):
            name = f"private-source.gpg.part-{number:03d}"
            expected = checksums.get(name)
            if expected is None:
                raise ValueError(f"missing checksum for source part {name}")
            stream.write(index.read_matching(name, expected))
    encrypted_line = companion("ENCRYPTED.sha256").decode("utf-8").strip()
    expected_encrypted = encrypted_line.split()[0]
    if sha256_file(encrypted) != expected_encrypted:
        raise ValueError("encrypted source checksum mismatch")
    return encrypted, transfer


def verify_key_fingerprint(private_key: Path, expected: str, gpg_home: Path) -> dict[str, str]:
    env = {**os.environ, "GNUPGHOME": str(gpg_home)}
    gpg_home.mkdir(mode=0o700, parents=True)
    os.chmod(gpg_home, 0o700)
    _run(["gpg", "--batch", "--import", str(private_key)], env=env, capture=True)
    listing = _run(["gpg", "--batch", "--with-colons", "--list-secret-keys"], env=env, capture=True).stdout
    fingerprints: list[str] = []
    for line in listing.splitlines():
        fields = line.split(":")
        if fields[0] == "fpr":
            fingerprints.append(fields[9])
    if expected not in fingerprints:
        raise ValueError(f"private key fingerprint mismatch; expected {expected}")
    return env


def _decrypt_source(encrypted: Path, private_key: Path, work: Path, expected_fingerprint: str = EXPECTED_SOURCE_FINGERPRINT) -> Path:
    gpg_home = work / "gnupg"
    env = verify_key_fingerprint(private_key, expected_fingerprint, gpg_home)
    plaintext = work / "private-source-package.tar.zst"
    _run(["gpg", "--batch", "--yes", "--output", str(plaintext), "--decrypt", str(encrypted)], env=env, capture=True)
    return plaintext


def restore_git_bundle(package_dir: Path, destination: Path, project: str, branch: str | None) -> dict[str, Any]:
    private_manifest = json.loads((package_dir / "PRIVATE-MANIFEST.json").read_text(encoding="utf-8"))
    if private_manifest.get("schema_version") != 1 or private_manifest.get("project") != project:
        raise ValueError("private source package manifest mismatch")
    expected_repository = "Semogtw/goanime-mobile" if project == "goanime" else "Semogtw/Zapzap"
    if private_manifest.get("repository") != expected_repository:
        raise ValueError("private repository mismatch")
    if destination.exists():
        if any(destination.iterdir()):
            raise ValueError(f"destination is not empty: {destination}")
        destination.rmdir()
    if private_manifest.get("format") == "bundle":
        bundle = package_dir / "repository.bundle"
        if not bundle.is_file():
            raise ValueError("repository.bundle missing")
        _run(["git", "clone", str(bundle), str(destination)])
        _run(["git", "-C", str(destination), "remote", "set-url", "origin", PROJECT_REMOTES[project]])
        if branch:
            local = _run(["git", "-C", str(destination), "branch", "--list", branch], capture=True).stdout.strip()
            if local:
                _run(["git", "-C", str(destination), "switch", branch])
            else:
                remote = _run(["git", "-C", str(destination), "branch", "-r", "--list", f"origin/{branch}"], capture=True).stdout.strip()
                if not remote:
                    raise ValueError(f"requested branch not found in bundle: {branch}")
                _run(["git", "-C", str(destination), "switch", "-c", branch, "--track", f"origin/{branch}"])
        _run(["git", "-C", str(destination), "fsck", "--full", "--no-dangling"], capture=True)
    elif private_manifest.get("format") == "snapshot":
        snapshot = package_dir / "snapshot.tar.zst"
        safe_extract_tar(snapshot, destination, zstd=True)
    else:
        raise ValueError("unsupported private source package format")
    return private_manifest


def _host_architecture() -> str:
    machine = platform.machine().lower()
    return "x86_64" if machine in {"x86_64", "amd64"} else machine


def choose_manifests(index: DownloadIndex, profile: str, profiles_root: Path, require_exact: bool) -> list[tuple[dict[str, Any], ZipMember | Path]]:
    registry = load_profiles(profiles_root)
    required = expand_profile(profile, registry)
    available = index.artifact_manifests()
    chosen: list[tuple[dict[str, Any], ZipMember | Path]] = []
    for required_profile in required:
        candidates = [item for item in available if item[0]["profile"] == required_profile]
        if not candidates:
            raise ValueError(f"missing artifact manifest for profile {required_profile}")
        candidates.sort(key=lambda item: (item[0]["created_at"], item[0]["run_id"]), reverse=True)
        manifest, source = candidates[0]
        if manifest["platform"] != "linux" or manifest["architecture"] != _host_architecture():
            raise ValueError(f"incompatible host for {required_profile}")
        if manifest["compatibility"]["minimum_restore_version"] > RESTORE_VERSION:
            raise ValueError(f"restore client too old for {required_profile}")
        project = registry[required_profile]["project"]
        if require_exact and project and manifest["lock_mode"] != "private-exact":
            raise ValueError(f"exact-lock artifact required for {required_profile}")
        chosen.append((manifest, source))
        index.mark_used(source)
    return chosen



def validate_exact_lock_fingerprints(checkout: Path, manifests: list[tuple[dict[str, Any], ZipMember | Path]], profiles_root: Path, project: str) -> dict[str, str]:
    verified: dict[str, str] = {}
    for manifest, _source in manifests:
        if manifest["lock_mode"] != "private-exact":
            continue
        profile = manifest["profile"]
        current = collect_lock_inputs(checkout, profile, profiles_root, project)
        if current["lock_fingerprint"] != manifest["lock_fingerprint"]:
            raise ValueError(f"toolchain lock fingerprint mismatch for {profile}")
        verified[profile] = current["lock_fingerprint"]
    return verified

def _assemble_v2(index: DownloadIndex, manifest: dict[str, Any], output: Path) -> None:
    with output.open("wb") as stream:
        for part in manifest["parts"]:
            data = index.read_matching(part["name"], part["sha256"])
            if len(data) != part["size"]:
                raise ValueError(f"part size mismatch: {part['name']}")
            stream.write(data)
    if output.stat().st_size != manifest["archive"]["size"] or sha256_file(output) != manifest["archive"]["sha256"]:
        raise ValueError(f"archive mismatch for {manifest['artifact_set_id']}")


def extract_toolchains(index: DownloadIndex, manifests: list[tuple[dict[str, Any], ZipMember | Path]], destination: Path, work: Path) -> list[dict[str, Any]]:
    destination.mkdir(parents=True, exist_ok=True)
    installed: list[dict[str, Any]] = []
    for manifest, _source in manifests:
        archive = work / manifest["archive"]["name"]
        _assemble_v2(index, manifest, archive)
        members = _validate_tar_members(archive, zstd=True)
        top_levels = {PurePosixPath(name).parts[0] for name in members if PurePosixPath(name).parts}
        if len(top_levels) != 1:
            raise ValueError(f"artifact must contain one top-level directory: {manifest['artifact_set_id']}")
        safe_extract_tar(archive, destination, zstd=True)
        root = destination / next(iter(top_levels))
        if not root.is_dir():
            raise ValueError(f"extracted root missing for {manifest['artifact_set_id']}")
        manifest_path = root / ".artifact-set.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        completed = _run([sys.executable, str(Path(__file__).with_name("doctor.py")), "--manifest", str(manifest_path), "--root", str(root), "--json"], capture=True)
        doctor = json.loads(completed.stdout)
        installed.append({"manifest": manifest, "root": str(root), "doctor": doctor})
    return installed


def write_activation_script(installed: list[dict[str, Any]], path: Path) -> None:
    lines = ["#!/usr/bin/env bash", "set -euo pipefail", 'workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"']
    for item in installed:
        root = Path(item["root"])
        activation = root / item["manifest"]["activation_script"]
        if not activation.is_file():
            raise ValueError(f"activation script missing: {activation}")
        lines.append(f"source {json.dumps(str(activation))}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o755)


def restore(args: argparse.Namespace) -> dict[str, Any]:
    downloads = args.downloads.resolve()
    destination = args.destination.resolve()
    private_key = args.private_key.resolve()
    if not downloads.is_dir():
        raise ValueError("downloads directory not found")
    if not private_key.is_file():
        raise ValueError("private key file not found")
    for command in ("git", "gpg", "tar", "zstd"):
        if shutil.which(command) is None:
            raise ValueError(f"missing command: {command}")

    index = DownloadIndex(downloads)
    work_parent = destination.parent
    work_parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="offline-restore-", dir=work_parent))
    report_path = args.report.resolve() if args.report else destination.parent / f"{args.project}-restore-report.json"
    try:
        encrypted, transfer = _verify_source_transfer(index, args.project, work, args.expected_source_fingerprint)
        plaintext = _decrypt_source(encrypted, private_key, work, args.expected_source_fingerprint)
        package_dir = work / "source-package"
        safe_extract_tar(plaintext, package_dir, zstd=True)
        private_manifest = restore_git_bundle(package_dir, destination, args.project, args.branch)

        profiles_root = args.profiles.resolve()
        manifests = choose_manifests(index, args.profile, profiles_root, args.require_exact_lock)
        verified_locks = validate_exact_lock_fingerprints(destination, manifests, profiles_root, args.project)
        toolchains_root = destination.parent / f".{destination.name}-toolchains"
        if toolchains_root.exists():
            shutil.rmtree(toolchains_root)
        installed = extract_toolchains(index, manifests, toolchains_root, work)
        activation = destination.parent / f"activate-{destination.name}.sh"
        write_activation_script(installed, activation)

        report = {
            "schema_version": 1,
            "status": "ready",
            "restored_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "project": args.project,
            "profile": args.profile,
            "destination": str(destination),
            "activation_script": str(activation),
            "source": {
                "workflow_run_id": transfer.get("workflow_run_id"),
                "mode": transfer.get("mode"),
                "resolved_commit": private_manifest.get("resolved_commit"),
            },
            "verified_lock_fingerprints": verified_locks,
            "toolchains": [
                {
                    "profile": item["manifest"]["profile"],
                    "artifact_set_id": item["manifest"]["artifact_set_id"],
                    "lock_mode": item["manifest"]["lock_mode"],
                    "lock_fingerprint": item["manifest"]["lock_fingerprint"],
                    "doctor": item["doctor"],
                }
                for item in installed
            ],
        }
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if not args.keep_downloads:
            for archive in index.used_archives:
                archive.unlink(missing_ok=True)
        return report
    except Exception as error:
        failure = {
            "schema_version": 1,
            "status": "failed",
            "failed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "project": args.project,
            "profile": args.profile,
            "destination": str(destination),
            "error": str(error),
        }
        report_path.write_text(json.dumps(failure, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        raise
    finally:
        if args.keep_temporary:
            print(f"temporary restore directory kept: {work}", file=sys.stderr)
        else:
            shutil.rmtree(work, ignore_errors=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True, choices=sorted(PROJECT_REMOTES))
    parser.add_argument("--downloads", required=True, type=Path)
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--branch")
    parser.add_argument("--profiles", type=Path, default=Path(__file__).resolve().parents[1] / "profiles")
    parser.add_argument("--require-exact-lock", action="store_true")
    parser.add_argument("--keep-temporary", action="store_true")
    parser.add_argument("--keep-downloads", action="store_true")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--expected-source-fingerprint", default=EXPECTED_SOURCE_FINGERPRINT, help=argparse.SUPPRESS)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        report = restore(args)
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError, zipfile.BadZipFile) as error:
        print(f"workspace restoration failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
