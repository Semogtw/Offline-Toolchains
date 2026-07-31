from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

from scripts.restore_workspace import DownloadIndex, safe_extract_tar


class RestoreWorkspaceTests(unittest.TestCase):
    maxDiff = None

    def _run(self, command: list[str], **kwargs):
        return subprocess.run(command, check=True, text=True, capture_output=True, **kwargs)

    def _gpg_key(self, root: Path) -> tuple[Path, str, dict[str, str]]:
        home = root / "gpg-home"
        home.mkdir(mode=0o700)
        env = {**os.environ, "GNUPGHOME": str(home)}
        self._run(["gpg", "--batch", "--passphrase", "", "--quick-generate-key", "Restore Test <restore@example.invalid>", "rsa2048", "encr", "1d"], env=env)
        listing = self._run(["gpg", "--batch", "--with-colons", "--list-secret-keys"], env=env).stdout
        fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
        private = root / "private.asc"
        with private.open("wb") as stream:
            subprocess.run(["gpg", "--batch", "--armor", "--export-secret-keys", fingerprint], env=env, check=True, stdout=stream)
        return private, fingerprint, env

    def _source_artifacts(self, root: Path, project: str, env: dict[str, str], fingerprint: str) -> Path:
        repository = root / "source-repo"
        repository.mkdir()
        self._run(["git", "init", "-b", "main"], cwd=repository)
        self._run(["git", "config", "user.name", "Test"], cwd=repository)
        self._run(["git", "config", "user.email", "test@example.invalid"], cwd=repository)
        (repository / "README.md").write_text("offline restore\n")
        self._run(["git", "add", "."], cwd=repository)
        self._run(["git", "commit", "-m", "initial"], cwd=repository)
        package = root / "source-package"
        package.mkdir()
        bundle = package / "repository.bundle"
        self._run(["git", "bundle", "create", str(bundle), "--all"], cwd=repository)
        commit = self._run(["git", "rev-parse", "HEAD"], cwd=repository).stdout.strip()
        private_manifest = {
            "schema_version": 1,
            "project": project,
            "repository": "Semogtw/Zapzap" if project == "zapzap" else "Semogtw/goanime-mobile",
            "mode": "full",
            "requested_ref": "",
            "resolved_commit": commit,
            "format": "bundle",
        }
        (package / "PRIVATE-MANIFEST.json").write_text(json.dumps(private_manifest))
        (package / "REFS.txt").write_text(f"refs/heads/main\t{commit}\n")
        plaintext = root / "source.tar.zst"
        self._run(["tar", "-C", str(package), "-I", "zstd -T0 -3", "-cf", str(plaintext), "."])
        encrypted = root / "private-source.gpg"
        self._run(["gpg", "--batch", "--yes", "--trust-model", "always", "--recipient", fingerprint, "--output", str(encrypted), "--encrypt", str(plaintext)], env=env)
        downloads = root / "downloads"
        downloads.mkdir()
        part = encrypted.read_bytes()
        part_name = "private-source.gpg.part-000"
        part_hash = hashlib.sha256(part).hexdigest()
        transfer = {
            "schema_version": 1, "project": project, "mode": "full", "part_count": 1,
            "split_size": "400M", "encryption": "OpenPGP", "recipient_fingerprint": fingerprint,
            "workflow_run_id": "1", "created_utc": "2026-07-31T00:00:00Z",
        }
        with zipfile.ZipFile(downloads / "source-manifest.zip", "w") as handle:
            handle.writestr("TRANSFER.json", json.dumps(transfer))
            handle.writestr("SHA256SUMS.parts", f"{part_hash}  {part_name}\n")
            handle.writestr("ENCRYPTED.sha256", f"{part_hash}  private-source.gpg\n")
        with zipfile.ZipFile(downloads / "source-part.zip", "w") as handle:
            handle.writestr(part_name, part)
        return downloads

    def _toolchain_artifacts(self, root: Path, downloads: Path, fingerprint: str) -> None:
        package_root = root / "jdk21"
        (package_root / "jdk/bin").mkdir(parents=True)
        java = package_root / "jdk/bin/java"
        java.write_text("#!/bin/sh\necho openjdk version 21 >&2\n")
        java.chmod(0o755)
        activate = package_root / "activate.sh"
        activate.write_text("#!/bin/sh\nexport JAVA_HOME=\"$(cd \"$(dirname \"$0\")\" && pwd)/jdk\"\n")
        activate.chmod(0o755)
        built = root / "built"
        self._run([
            "python3", "scripts/build_artifact_set.py", "--profile", "jdk21", "--package", "jdk21",
            "--root", str(package_root), "--out", str(built), "--lock-mode", "not-applicable",
            "--lock-fingerprint", "0" * 64, "--builder-fingerprint", "1" * 64,
            "--workflow", "test", "--workflow-commit", "2" * 40, "--run-id", "12", "--part-size", "128",
        ])
        manifest = json.loads((built / "artifact-set.json").read_text())
        with zipfile.ZipFile(downloads / "jdk-manifest.zip", "w") as handle:
            for name in ("artifact-set.json", "PARTS.txt", "SHA256SUMS.parts", "SBOM.spdx.json"):
                handle.write(built / name, name)
        for part in manifest["parts"]:
            with zipfile.ZipFile(downloads / f"jdk-part-{part['index']}.zip", "w") as handle:
                handle.write(built / part["name"], part["name"])

    def test_restores_bundle_and_toolchain_end_to_end(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            private, fingerprint, env = self._gpg_key(root)
            downloads = self._source_artifacts(root, "zapzap", env, fingerprint)
            self._toolchain_artifacts(root, downloads, fingerprint)
            destination = root / "restored"
            report = root / "report.json"
            completed = subprocess.run([
                "python3", "scripts/restore_workspace.py", "--project", "zapzap", "--downloads", str(downloads),
                "--private-key", str(private), "--destination", str(destination), "--profile", "jdk21",
                "--profiles", str(Path("profiles").resolve()), "--keep-downloads", "--report", str(report),
                "--expected-source-fingerprint", fingerprint,
            ], cwd=Path.cwd(), text=True, capture_output=True)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual((destination / "README.md").read_text(), "offline restore\n")
            document = json.loads(report.read_text())
            self.assertEqual(document["status"], "ready")
            self.assertEqual(document["toolchains"][0]["doctor"]["status"], "ready")
            self.assertTrue((root / "activate-restored.sh").is_file())

    def test_rejects_source_fingerprint_before_decryption(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            downloads = root / "downloads"
            downloads.mkdir()
            transfer = {"schema_version": 1, "project": "zapzap", "part_count": 1, "recipient_fingerprint": "0" * 40}
            with zipfile.ZipFile(downloads / "manifest.zip", "w") as handle:
                handle.writestr("TRANSFER.json", json.dumps(transfer))
            index = DownloadIndex(downloads)
            from scripts.restore_workspace import _verify_source_transfer
            with self.assertRaisesRegex(ValueError, "fingerprint"):
                _verify_source_transfer(index, "zapzap", root / "work")

    def test_rejects_unsafe_tar_member(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            source = root / "file"
            source.write_text("bad")
            archive = root / "evil.tar.zst"
            subprocess.run(["tar", "-C", str(root), "--transform", "s#file#../escape#", "-I", "zstd", "-cf", str(archive), "file"], check=True)
            with self.assertRaisesRegex(ValueError, "unsafe tar"):
                safe_extract_tar(archive, root / "out")


if __name__ == "__main__":
    unittest.main()

class LockCompatibilityTests(unittest.TestCase):
    def test_exact_manifest_must_match_restored_checkout(self):
        from scripts.restore_workspace import validate_exact_lock_fingerprints
        from scripts.collect_lock_inputs import collect
        root=Path(tempfile.mkdtemp())
        try:
            profiles=root/'profiles'; profiles.mkdir()
            (profiles/'project.json').write_text(json.dumps({
                'name':'project','kind':'concrete','project':'goanime','packages':['project'],'requires':[],
                'activation_order':1,'lock_mode':'private-exact','lock_inputs':['pubspec.yaml'],
                'doctor_checks':[],'platform':'linux','architecture':'x86_64'}))
            checkout=root/'checkout'; checkout.mkdir(); (checkout/'pubspec.yaml').write_text('name: one\n')
            fingerprint=collect(checkout,'project',profiles,'goanime')['lock_fingerprint']
            manifest={'profile':'project','lock_mode':'private-exact','lock_fingerprint':fingerprint}
            self.assertEqual(validate_exact_lock_fingerprints(checkout,[(manifest,Path('x'))],profiles,'goanime'),{'project':fingerprint})
            (checkout/'pubspec.yaml').write_text('name: two\n')
            with self.assertRaisesRegex(ValueError,'lock fingerprint mismatch'):
                validate_exact_lock_fingerprints(checkout,[(manifest,Path('x'))],profiles,'goanime')
        finally:
            shutil.rmtree(root)
