"""Structural and small-fixture contracts for the Yuzono reference runtime."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "goanime-yuzono-ptbr-anime-full-audit.yml"
BUILD_SCRIPT = ROOT / "scripts" / "goanime_yuzono" / "build_reference_runtime.sh"
WRITE_SCRIPT = ROOT / "scripts" / "goanime_yuzono" / "write_reference_manifest.py"
VERIFY_SCRIPT = ROOT / "scripts" / "goanime_yuzono" / "verify_reference_manifest.py"
EXPECTED_FIELDS = {
    "schemaVersion",
    "goAnimeSourceSha",
    "anikkuSha",
    "flexibleAdapterSha",
    "appApkSha256",
    "testApkSha256",
    "jdkMajor",
    "buildAttempt",
    "fallbackUsed",
}
SOURCE_SHA = "a" * 40
ANIKKU_SHA = "41fefe566a00e8eb38dfa7f11802c8bfbe5c16e7"
FLEXIBLE_ADAPTER_SHA = "c80135339bcff5f7f8c2c2380329dfc155b26232"


def job_body(workflow: str, name: str) -> str:
    match = re.search(
        rf"\n  {re.escape(name)}:\n(?P<body>.*?)(?=\n  [a-z][a-z0-9-]*:\n|\Z)",
        workflow,
        re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"workflow job not found: {name}")
    return match.group("body")


def run_script(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(script), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class ReferenceRuntimeContractTest(unittest.TestCase):
    def test_single_reference_runtime_job_builds_once_and_execution_jobs_consume_it(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        reference = job_body(workflow, "reference-runtime")
        canary = job_body(workflow, "canary")
        full_shard = job_body(workflow, "full-shard")

        self.assertEqual(workflow.count("\n  reference-runtime:\n"), 1)
        self.assertEqual(reference.count("build_reference_runtime.sh"), 1)
        self.assertIn("actions/upload-artifact@", reference)
        self.assertIn("anikku-app-debug.apk", reference)
        self.assertIn("anikku-app-debug-androidTest.apk", reference)
        self.assertIn("reference-runtime-manifest.json", reference)
        self.assertIn("yuzono-reference-runtime-", reference)

        for execution_job in (canary, full_shard):
            self.assertIn("actions/download-artifact@", execution_job)
            self.assertIn("yuzono-reference-runtime-", execution_job)
            self.assertIn("verify_reference_manifest.py", execution_job)
            self.assertIn("--manifest", execution_job)
            self.assertIn("--app-apk", execution_job)
            self.assertIn("--test-apk", execution_job)
            self.assertIn("run_emulator_probes.sh", execution_job)
            self.assertNotIn(":app:assembleDebug", execution_job)
            self.assertNotIn("Checkout pinned Anikku runtime", execution_job)
            self.assertNotIn("inject_harness.py", execution_job)

    def test_reference_runtime_build_and_verification_are_bound_to_all_pins(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        reference = job_body(workflow, "reference-runtime")
        self.assertIn("--goanime-source-sha", reference)
        self.assertIn("--anikku-sha", reference)
        self.assertIn("--flexible-adapter-sha", reference)
        self.assertIn(ANIKKU_SHA, workflow)
        self.assertIn(FLEXIBLE_ADAPTER_SHA, workflow)

    def test_only_reference_runtime_job_may_assemble_the_pinned_app(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(":app:assembleDebug", BUILD_SCRIPT.read_text(encoding="utf-8"))
        self.assertIn(":app:assembleDebugAndroidTest", BUILD_SCRIPT.read_text(encoding="utf-8"))
        self.assertNotIn(":app:assembleDebug", job_body(workflow, "reference-runtime"))
        for job in ("canary", "full-shard"):
            self.assertNotIn(":app:assembleDebug", job_body(workflow, job))
            self.assertNotIn(":app:assembleDebugAndroidTest", job_body(workflow, job))

    def test_flexible_adapter_fallback_is_explicitly_guarded_and_exact_sha_bound(self) -> None:
        self.assertTrue(BUILD_SCRIPT.is_file(), "T02 build script is missing")
        script = BUILD_SCRIPT.read_text(encoding="utf-8")
        self.assertIn(FLEXIBLE_ADAPTER_SHA, script)
        self.assertIn("FORCE_FLEXIBLE_ADAPTER_FALLBACK", script)
        self.assertIn("rev-parse HEAD", script)
        self.assertIn("checkout --quiet --detach", script)
        self.assertIn("fallbackUsed", script)
        self.assertIn("flexible_adapter_fallback_aar_sha256", script)


class ManifestContractTest(unittest.TestCase):
    def make_inputs(self, directory: Path) -> tuple[Path, Path, Path]:
        app = directory / "anikku-app-debug.apk"
        test = directory / "anikku-app-debug-androidTest.apk"
        manifest = directory / "reference-runtime-manifest.json"
        app.write_bytes(b"sanitized app fixture")
        test.write_bytes(b"sanitized test fixture")
        return app, test, manifest

    def test_writer_emits_exact_schema_and_sha256_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app, test, manifest = self.make_inputs(Path(temporary))
            result = run_script(
                WRITE_SCRIPT,
                "--output",
                str(manifest),
                "--goanime-source-sha",
                SOURCE_SHA,
                "--anikku-sha",
                ANIKKU_SHA,
                "--flexible-adapter-sha",
                FLEXIBLE_ADAPTER_SHA,
                "--app-apk",
                str(app),
                "--test-apk",
                str(test),
                "--jdk-major",
                "17",
                "--build-attempt",
                "2",
                "--fallback-used",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(set(payload), EXPECTED_FIELDS)
            self.assertEqual(payload["schemaVersion"], 1)
            self.assertEqual(payload["goAnimeSourceSha"], SOURCE_SHA)
            self.assertEqual(payload["anikkuSha"], ANIKKU_SHA)
            self.assertEqual(payload["flexibleAdapterSha"], FLEXIBLE_ADAPTER_SHA)
            self.assertEqual(payload["appApkSha256"], hashlib.sha256(app.read_bytes()).hexdigest())
            self.assertEqual(payload["testApkSha256"], hashlib.sha256(test.read_bytes()).hexdigest())
            self.assertEqual(payload["jdkMajor"], 17)
            self.assertEqual(payload["buildAttempt"], 2)
            self.assertTrue(payload["fallbackUsed"])

    def test_verifier_accepts_matching_fixture_and_rejects_digest_or_identity_tampering(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app, test, manifest = self.make_inputs(Path(temporary))
            written = run_script(
                WRITE_SCRIPT,
                "--output",
                str(manifest),
                "--goanime-source-sha",
                SOURCE_SHA,
                "--anikku-sha",
                ANIKKU_SHA,
                "--flexible-adapter-sha",
                FLEXIBLE_ADAPTER_SHA,
                "--app-apk",
                str(app),
                "--test-apk",
                str(test),
                "--jdk-major",
                "17",
                "--build-attempt",
                "1",
                "--no-fallback-used",
            )
            self.assertEqual(written.returncode, 0, written.stderr)
            common = (
                "--manifest",
                str(manifest),
                "--app-apk",
                str(app),
                "--test-apk",
                str(test),
                "--goanime-source-sha",
                SOURCE_SHA,
                "--anikku-sha",
                ANIKKU_SHA,
                "--flexible-adapter-sha",
                FLEXIBLE_ADAPTER_SHA,
                "--jdk-major",
                "17",
            )
            accepted = run_script(VERIFY_SCRIPT, *common)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            app.write_bytes(b"tampered app fixture")
            rejected_digest = run_script(VERIFY_SCRIPT, *common)
            self.assertNotEqual(rejected_digest.returncode, 0)
            self.assertIn("digest", (rejected_digest.stderr + rejected_digest.stdout).lower())

            app.write_bytes(b"sanitized app fixture")
            rejected_identity = run_script(
                VERIFY_SCRIPT,
                *common[:-2],
                "--flexible-adapter-sha",
                "b" * 40,
                "--jdk-major",
                "17",
            )
            self.assertNotEqual(rejected_identity.returncode, 0)
            self.assertIn("identity", (rejected_identity.stderr + rejected_identity.stdout).lower())

    def test_verifier_rejects_missing_artifacts_and_unknown_manifest_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app, test, manifest = self.make_inputs(Path(temporary))
            written = run_script(
                WRITE_SCRIPT,
                "--output",
                str(manifest),
                "--goanime-source-sha",
                SOURCE_SHA,
                "--anikku-sha",
                ANIKKU_SHA,
                "--flexible-adapter-sha",
                FLEXIBLE_ADAPTER_SHA,
                "--app-apk",
                str(app),
                "--test-apk",
                str(test),
                "--jdk-major",
                "17",
                "--build-attempt",
                "1",
                "--no-fallback-used",
            )
            self.assertEqual(written.returncode, 0, written.stderr)
            common = (
                "--manifest",
                str(manifest),
                "--app-apk",
                str(app),
                "--test-apk",
                str(test),
                "--goanime-source-sha",
                SOURCE_SHA,
                "--anikku-sha",
                ANIKKU_SHA,
                "--flexible-adapter-sha",
                FLEXIBLE_ADAPTER_SHA,
                "--jdk-major",
                "17",
            )
            test.unlink()
            missing = run_script(VERIFY_SCRIPT, *common)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("missing", (missing.stderr + missing.stdout).lower())

            test.write_bytes(b"sanitized test fixture")
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["unexpected"] = "rejected"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            extra = run_script(VERIFY_SCRIPT, *common)
            self.assertNotEqual(extra.returncode, 0)
            self.assertIn("fields", (extra.stderr + extra.stdout).lower())

    def test_cli_help_is_loadable(self) -> None:
        for script in (WRITE_SCRIPT, VERIFY_SCRIPT):
            result = run_script(script, "--help")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("usage:", result.stdout.lower())


class CanaryContractTest(unittest.TestCase):
    def test_manifest_verification_precedes_emulator_execution_in_every_execution_job(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for name in ("canary", "full-shard"):
            body = job_body(workflow, name)
            self.assertLess(body.index("verify_reference_manifest.py"), body.index("run_emulator_probes.sh"))

    def test_reference_runtime_is_not_required_for_deterministic_mode(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        reference = job_body(workflow, "reference-runtime")
        self.assertRegex(reference, r"mode\s*!=\s*'deterministic'")


if __name__ == "__main__":
    unittest.main()
