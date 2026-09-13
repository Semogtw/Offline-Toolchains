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
SANITIZE_SCRIPT = ROOT / "scripts" / "goanime_yuzono" / "sanitize_audit_outputs.py"
VALIDATE_CONTINUATION_SCRIPT = ROOT / "scripts" / "goanime_yuzono" / "validate_continuation_request.py"
VERIFY_CANARY_SCRIPT = ROOT / "scripts" / "goanime_yuzono" / "verify_canary.py"
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
        for execution_job in (reference, canary, full_shard):
            self.assertIn("Checkout Toolchains workflow", execution_job)
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

    def test_continuations_reuse_the_origin_runtime_and_never_rebuild(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        deterministic = job_body(workflow, "deterministic")
        reference = job_body(workflow, "reference-runtime")
        finalizer = job_body(workflow, "finalize-full")

        self.assertIn("reference_runtime_run_id", workflow)
        self.assertIn("DISPATCH_REFERENCE_RUNTIME_RUN_ID", deterministic)
        self.assertIn("reference_runtime_run_id:", deterministic)
        self.assertIn("run-id: ${{ needs.deterministic.outputs.reference_runtime_run_id }}", reference)
        self.assertIn("reference_runtime_run_id == ''", reference)
        self.assertIn("reference_runtime_run_id != ''", reference)
        self.assertIn("reference_runtime_run_id", finalizer)
        self.assertIn("-f reference_runtime_run_id=", finalizer)
        self.assertIn("reference runtime origin", reference.lower())
        self.assertIn("reference_run_id", reference)
        self.assertIn("verify_reference_manifest.py", reference)
        self.assertIn("validate_continuation_request.py", deterministic)
        self.assertIn("continuation_index > 0", VALIDATE_CONTINUATION_SCRIPT.read_text(encoding="utf-8"))
        self.assertIn("continuation_index == '0'", reference)

    def test_continuation_without_origin_runtime_is_fail_closed(self) -> None:
        deterministic = job_body(WORKFLOW.read_text(encoding="utf-8"), "deterministic")
        self.assertIn("parent_run_id", deterministic)
        self.assertRegex(
            deterministic,
            r"parent_run_id.*reference_runtime_run_id|reference_runtime_run_id.*parent_run_id",
        )
        self.assertIn("must carry reference runtime", deterministic.lower())

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

    def test_flexible_adapter_fallback_bootstraps_missing_dependency_with_jdk8(self) -> None:
        script = BUILD_SCRIPT.read_text(encoding="utf-8")
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("FLEXIBLE_ADAPTER_JAVA_HOME", script)
        self.assertIn("java-ordered-properties/1.0.4", script)
        self.assertIn("803766d9fecc4112c72b39951e60c2e60156c2b100c3aa11df98b27583ba3eb6", script)
        self.assertIn("57c085b9815c56a501a40cfbfa2dbeb077f997bb3a6c92ac13c8bd05ef182c8c", script)
        self.assertIn("dependencySubstitution", script)
        self.assertIn("Set up Temurin JDK 8 for exact FlexibleAdapter fallback", workflow)
        self.assertIn("JAVA_HOME_8_X64", workflow)


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

    def test_writer_requires_an_explicit_fallback_decision(self) -> None:
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
                "1",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(manifest.exists())

    def test_writer_and_verifier_reject_an_arbitrary_flexible_adapter_pin(self) -> None:
        arbitrary = "b" * 40
        with tempfile.TemporaryDirectory() as temporary:
            app, test, manifest = self.make_inputs(Path(temporary))
            writer = run_script(
                WRITE_SCRIPT,
                "--output",
                str(manifest),
                "--goanime-source-sha",
                SOURCE_SHA,
                "--anikku-sha",
                ANIKKU_SHA,
                "--flexible-adapter-sha",
                arbitrary,
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
            self.assertNotEqual(writer.returncode, 0)
            self.assertFalse(manifest.exists())

            valid = run_script(
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
            self.assertEqual(valid.returncode, 0, valid.stderr)
            verifier = run_script(
                VERIFY_SCRIPT,
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
                arbitrary,
                "--jdk-major",
                "17",
            )
            self.assertNotEqual(verifier.returncode, 0)

    def test_cli_help_is_loadable(self) -> None:
        for script in (WRITE_SCRIPT, VERIFY_SCRIPT, SANITIZE_SCRIPT, VERIFY_CANARY_SCRIPT):
            result = run_script(script, "--help")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("usage:", result.stdout.lower())


class SanitizedOutputContractTest(unittest.TestCase):
    def test_instrumentation_failure_result_lines_are_allowlisted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audit-output"
            output.mkdir()
            (output / "verification.json").write_text(
                json.dumps(
                    {
                        "consistent": True,
                        "complete": False,
                        "scoped_count": 0,
                        "accepted_terminal_count": 0,
                        "pending_count": 0,
                        "blocker_count": 0,
                        "missing_result_count": 0,
                        "identity_mismatch_count": 0,
                        "violations": [],
                    }
                ),
                encoding="utf-8",
            )
            log_dir = Path(temporary) / "logs"
            log_dir.mkdir()
            (log_dir / "instrumentation.log").write_text(
                "GoAnime probe instrumentation registration:\n"
                "instrumentation:eu.kanade.tachiyomi.GoAnimeYuzonoProbeInstrumentation (target=app.anikku.dev)\n"
                "remaining_soft_seconds=12345\n"
                "INSTRUMENTATION_RESULT: failure=IllegalStateException\n"
                "INSTRUMENTATION_RESULT: probeResult=runner-instrumentation\n"
                "INSTRUMENTATION_STATUS_CODE: -1\n"
                "INSTRUMENTATION_CODE: -1\n",
                encoding="utf-8",
            )
            result = run_script(
                SANITIZE_SCRIPT,
                "--root",
                str(output),
                "--logs-dir",
                str(log_dir),
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_current_v3_report_shape_is_allowlisted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audit-output"
            output.mkdir()
            (output / "report.md").write_text(
                "\n".join(
                    (
                        "# Yuzono PT-BR Anime Probe",
                        "",
                        "| Metric | Value |",
                        "| --- | ---: |",
                        "| Audit complete | no |",
                        "| Audit blockers | 1 |",
                        "| Promotion candidates | 0 |",
                        "| GoAnime baseline unique titles | 10 |",
                        "| Candidate raw occurrences | 2 |",
                        "| Candidate normalized occurrences | 2 |",
                        "| Candidate union unique titles | 2 |",
                        "| Cross-provider duplicate occurrences | 0 |",
                        "| Candidate exclusive titles | 2 |",
                        "| Combined unique titles | 12 |",
                        "",
                        "| Provider | Status | Stage | Language | Catalog complete | Titles | Overlap | Exclusive | Incremental unique | Resolution samples | Playback samples | Evidence | Terminal media | Failure |",
                        "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |",
                        "| AnimeFire | partial | catalog | sub | yes | 2 | 0 | 2 | 2 | 1 | 1 | E5 | yes | - |",
                        "",
                        "## Audit blockers",
                        "",
                        "- yuzono.pt.animefire",
                        "",
                    )
                ),
                encoding="utf-8",
            )
            result = run_script(SANITIZE_SCRIPT, "--root", str(output))
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_aggregate_v3_provider_evidence_is_allowlisted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audit-output"
            output.mkdir()
            (output / "results.json").write_text(
                json.dumps(
                    {
                        "providerCount": 1,
                        "statusCounts": {"ready": 1},
                        "baselineGoAnimeUniqueTitles": 0,
                        "candidateRawOccurrences": 1,
                        "candidateNormalizedOccurrences": 1,
                        "candidateUnionUniqueTitles": 1,
                        "crossProviderDuplicateOccurrences": 0,
                        "candidateExclusiveUniqueTitles": 1,
                        "combinedUniqueTitles": 1,
                        "candidateExclusiveTitles": ["Título seguro"],
                        "identityMappingMode": "normalized-title-only",
                        "canonicalMatched": 0,
                        "canonicalUnresolved": 1,
                        "auditComplete": True,
                        "auditBlockers": [],
                        "promotionCandidates": [],
                        "promotionRejected": {},
                        "workflowEvidence": {
                            "schemaVersion": 1,
                            "fullShardResult": "success",
                            "shards": [
                                {
                                    "shard": 0,
                                    "modules": ["animefire"],
                                    "jobConclusion": "success",
                                    "providerExecutionStarted": True,
                                    "aggregateConclusion": "success",
                                }
                            ],
                        },
                        "providers": [
                            {
                                "sourceId": "yuzono.pt.animefire",
                                "module": "animefire",
                                "displayName": "AnimeFire",
                                "status": "ready",
                                "stage": "stream",
                                "languageMode": "sub",
                                "pagesVisited": 1,
                                "catalogueComplete": True,
                                "catalogueTermination": "natural-end",
                                "rawTitleCount": 1,
                                "distinctRawTitleCount": 1,
                                "normalizedTitleCount": 1,
                                "overlapWithGoAnime": 0,
                                "exclusiveVsGoAnime": 1,
                                "normalizationCollisions": 0,
                                "incrementalUniqueContribution": 1,
                                "incrementalExclusiveContribution": 1,
                                "playbackSampleCount": 1,
                                "resolutionSampleCount": 1,
                                "failureKind": None,
                                "schemaVersion": 3,
                                "executionIdentity": {
                                    "extensionPackage": "safe.package",
                                    "extensionClass": "safe.package.Source",
                                    "extensionApkSha256": "a" * 64,
                                },
                                "sampleLineage": {
                                    "catalogueDigest": "b" * 64,
                                    "animeOrdinal": 0,
                                    "animeLabelHash": "c" * 64,
                                    "episodeOrdinal": 0,
                                    "episodeLabelHash": "d" * 64,
                                    "resolverMode": "direct",
                                },
                                "mediaEvidence": {
                                    "transportObserved": True,
                                    "playerReadyObserved": True,
                                    "timeAdvancedObserved": True,
                                    "videoTrackObserved": True,
                                    "firstFrameObserved": True,
                                    "failureKind": None,
                                },
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            result = run_script(SANITIZE_SCRIPT, "--root", str(output))
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_path_identity_manifest_is_allowlisted_and_strict(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "probe-state" / "path-identity"
            root.mkdir(parents=True)
            identity = {
                "schemaVersion": 1,
                "module": "animefire",
                "sourceId": "yuzono.pt.animefire",
                "extensionPackage": "safe.animefire",
                "extensionApkSha256": "a" * 64,
                "providerExecutionStarted": False,
            }
            path = root / "animefire.json"
            path.write_text(json.dumps(identity), encoding="utf-8")
            accepted = run_script(SANITIZE_SCRIPT, "--root", str(root.parent))
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            identity["unexpected"] = "rejected"
            path.write_text(json.dumps(identity), encoding="utf-8")
            rejected = run_script(SANITIZE_SCRIPT, "--root", str(root.parent))
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("schema", (rejected.stderr + rejected.stdout).lower())

    def test_recursive_sanitized_fixture_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "probe-state"
            (root / "providers").mkdir(parents=True)
            (root / "checkpoints").mkdir()
            (root / "providers" / "animefire.json").write_text(
                json.dumps(
                    {
                        "sourceId": "yuzono.pt.animefire",
                        "module": "animefire",
                        "displayName": "AnimeFire",
                        "status": "partial",
                        "stage": "catalog",
                        "languageMode": "unknown",
                        "titles": ["Título seguro"],
                        "pagesVisited": 1,
                        "catalogueComplete": False,
                        "catalogueTermination": "safety-ceiling",
                        "rawTitleCount": 1,
                        "distinctRawTitleCount": 1,
                        "playbackSampleCount": 0,
                        "failureKind": "catalogue-truncated",
                    }
                ),
                encoding="utf-8",
            )
            (root / "checkpoints" / "animefire.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 2,
                        "generationId": "generation-1",
                        "goAnimeSourceSha": SOURCE_SHA,
                        "goAnimeBaselineSha": SOURCE_SHA,
                        "upstreamRevision": "d" * 40,
                        "anikkuRevision": ANIKKU_SHA,
                        "sourceId": "yuzono.pt.animefire",
                        "stage": "classified",
                        "status": "partial",
                        "retryCount": 0,
                        "titleCount": 1,
                        "playbackSampleCount": 0,
                        "failureKind": "catalogue-truncated",
                    }
                ),
                encoding="utf-8",
            )
            log_dir = Path(temporary) / "logs"
            log_dir.mkdir()
            (log_dir / "instrumentation.log").write_text(
                "remaining_soft_seconds=12345\n"
                "INSTRUMENTATION_STATUS: id=AndroidJUnitRunner\n"
                "INSTRUMENTATION_CODE: 0\n",
                encoding="utf-8",
            )
            result = run_script(
                SANITIZE_SCRIPT,
                "--root",
                str(root),
                "--logs-dir",
                str(log_dir),
            )
            self.assertEqual(result.returncode, 0, result.stderr)

            verification_root = Path(temporary) / "audit-output"
            verification_root.mkdir()
            (verification_root / "verification.json").write_text(
                json.dumps(
                    {
                        "consistent": True,
                        "complete": False,
                        "scoped_count": 23,
                        "accepted_terminal_count": 7,
                        "pending_count": 16,
                        "blocker_count": 11,
                        "missing_result_count": 11,
                        "identity_mismatch_count": 0,
                        "violations": [],
                    }
                ),
                encoding="utf-8",
            )
            verification = run_script(SANITIZE_SCRIPT, "--root", str(verification_root))
            self.assertEqual(verification.returncode, 0, verification.stderr)

    def test_recursive_sanitized_fixture_accepts_v3_provider_identity_and_media_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "probe-state"
            provider_dir = root / "providers"
            provider_dir.mkdir(parents=True)
            provider = {
                "sourceId": "yuzono.pt.anikyuu",
                "module": "anikyuu",
                "displayName": "Anikyuu",
                "status": "ready",
                "stage": "stream",
                "languageMode": "sub",
                "titles": ["Synthetic title"],
                "pagesVisited": 1,
                "catalogueComplete": True,
                "catalogueTermination": "natural-end",
                "rawTitleCount": 1,
                "distinctRawTitleCount": 1,
                "playbackSampleCount": 1,
                "failureKind": None,
                "schemaVersion": 3,
                "executionIdentity": {
                    "extensionPackage": "safe.anikyuu",
                    "extensionClass": "safe.anikyuu.Source",
                    "extensionApkSha256": "a" * 64,
                },
                "sampleLineage": {
                    "catalogueDigest": "b" * 64,
                    "animeOrdinal": 0,
                    "animeLabelHash": "c" * 64,
                    "episodeOrdinal": 0,
                    "episodeLabelHash": "d" * 64,
                    "resolverMode": "direct",
                },
                "resolutionSampleCount": 1,
                "mediaEvidence": {
                    "transportObserved": True,
                    "playerReadyObserved": True,
                    "timeAdvancedObserved": True,
                    "videoTrackObserved": True,
                    "firstFrameObserved": True,
                    "failureKind": None,
                },
            }
            (provider_dir / "anikyuu.json").write_text(
                json.dumps(provider), encoding="utf-8"
            )
            result = run_script(SANITIZE_SCRIPT, "--root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_recursive_gate_rejects_unknown_fields_and_raw_transport_content(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "probe-state"
            provider_dir = root / "providers"
            provider_dir.mkdir(parents=True)
            (provider_dir / "animefire.json").write_text(
                json.dumps({"sourceId": "yuzono.pt.animefire", "unknownField": "x"}),
                encoding="utf-8",
            )
            unknown = run_script(SANITIZE_SCRIPT, "--root", str(root))
            self.assertNotEqual(unknown.returncode, 0)
            self.assertIn("schema", (unknown.stderr + unknown.stdout).lower())

            (provider_dir / "animefire.json").write_text(
                json.dumps(
                    {
                        "sourceId": "yuzono.pt.animefire",
                        "module": "animefire",
                        "displayName": "AnimeFire",
                        "status": "broken",
                        "stage": "discovered",
                        "languageMode": "unknown",
                        "titles": [],
                        "pagesVisited": 0,
                        "catalogueComplete": False,
                        "catalogueTermination": "error",
                        "rawTitleCount": 0,
                        "distinctRawTitleCount": 0,
                        "playbackSampleCount": 0,
                        "failureKind": "https://secret.invalid/raw",
                    }
                ),
                encoding="utf-8",
            )
            transport = run_script(SANITIZE_SCRIPT, "--root", str(root))
            self.assertNotEqual(transport.returncode, 0)
            self.assertIn("forbidden", (transport.stderr + transport.stdout).lower())

    def test_recursive_gate_rejects_nested_provider_and_checkpoint_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "probe-state"
            provider_dir = root / "providers" / "nested"
            checkpoint_dir = root / "checkpoints" / "nested"
            provider_dir.mkdir(parents=True)
            checkpoint_dir.mkdir(parents=True)
            provider = {
                "sourceId": "yuzono.pt.animefire",
                "module": "animefire",
                "displayName": "AnimeFire",
                "status": "partial",
                "stage": "catalog",
                "languageMode": "unknown",
                "titles": [],
                "pagesVisited": 0,
                "catalogueComplete": False,
                "catalogueTermination": "empty-catalog",
                "rawTitleCount": 0,
                "distinctRawTitleCount": 0,
                "playbackSampleCount": 0,
                "failureKind": "empty-catalog",
            }
            (provider_dir / "animefire.json").write_text(
                json.dumps(provider), encoding="utf-8"
            )
            checkpoint = {
                "schemaVersion": 2,
                "generationId": "generation-1",
                "goAnimeSourceSha": SOURCE_SHA,
                "goAnimeBaselineSha": SOURCE_SHA,
                "upstreamRevision": "d" * 40,
                "anikkuRevision": ANIKKU_SHA,
                "sourceId": "yuzono.pt.animefire",
                "stage": "classified",
                "status": "partial",
                "retryCount": 0,
                "titleCount": 0,
                "playbackSampleCount": 0,
                "failureKind": "empty-catalog",
            }
            (checkpoint_dir / "animefire.json").write_text(
                json.dumps(checkpoint), encoding="utf-8"
            )
            result = run_script(SANITIZE_SCRIPT, "--root", str(root))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("path", (result.stderr + result.stdout).lower())

    def test_materialized_summary_gate_rejects_malicious_state_without_echoing_payload(self) -> None:
        safe_summary = "\n".join(
            (
                "## Generation receipt",
                "",
                "- generation: `generation-1`",
                "- continuation index: `0`",
                "- reference runtime origin run: `123`",
                "- pending providers: `0`",
                "- GoAnime probe SHA: `" + SOURCE_SHA + "`",
                "- GoAnime baseline SHA: `" + SOURCE_SHA + "`",
                "- Yuzono SHA: `" + "b" * 40 + "`",
                "- Anikku SHA: `" + ANIKKU_SHA + "`",
                "- Scope: centralized module policy; isNsfw remains metadata and mixed-content anime modules remain candidates; current GoAnime PT production modules are canary/control-only; donghuanosekai, doramogo and muitohentai are excluded as non-conventional; audit-only, with no production registration",
                "",
            )
        )
        malicious_payload = "https://secret.invalid/path?token=do-not-print"
        with tempfile.TemporaryDirectory() as temporary:
            summary = Path(temporary) / "summary.md"
            summary.write_text(safe_summary, encoding="utf-8")
            accepted = run_script(SANITIZE_SCRIPT, "--summary-file", str(summary))
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            summary.write_text(
                safe_summary + f"- raw: {malicious_payload}\n", encoding="utf-8"
            )
            rejected = run_script(SANITIZE_SCRIPT, "--summary-file", str(summary))
            output = rejected.stderr + rejected.stdout
            self.assertNotEqual(rejected.returncode, 0)
            self.assertNotIn(malicious_payload, output)

    def test_workflow_gates_logs_and_outputs_before_upload_or_summary(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for name in ("reference-runtime", "canary", "prepare-full", "full-shard", "finalize-full"):
            body = job_body(workflow, name)
            self.assertIn("sanitize_audit_outputs.py", body)
            self.assertIn("Checkout Toolchains workflow", body)
            self.assertIn("test -f scripts/goanime_yuzono/sanitize_audit_outputs.py", body)
        for name in ("canary", "full-shard"):
            body = job_body(workflow, name)
            self.assertIn("RUNNER_TEMP", body)
            self.assertIn("> \"$raw_log\" 2>&1", body)
            self.assertLess(body.index("sanitize_audit_outputs.py"), body.index("actions/upload-artifact@"))
        finalizer = job_body(workflow, "finalize-full")
        self.assertIn("verify-state", finalizer)
        self.assertIn("--require-complete", finalizer)
        self.assertIn("--path-identity-dir consolidated-state/path-identity", finalizer)
        self.assertIn("workflowEvidence", finalizer)
        self.assertIn("Enforce independent generation completeness", finalizer)
        self.assertIn("steps.verify-generation.outcome == 'success'", finalizer)
        self.assertIn("reference-runtime-${{ needs.deterministic.outputs.generation_id }}", finalizer)
        self.assertLess(finalizer.index("sanitize_audit_outputs.py"), finalizer.index("GITHUB_STEP_SUMMARY"))
        self.assertIn("Materialize full-audit summary", finalizer)
        self.assertIn("--summary-file", finalizer)
        self.assertIn("sanitize-summary", finalizer)
        self.assertIn("steps.sanitize-summary.outcome == 'success'", finalizer)
        self.assertLess(finalizer.index("--summary-file"), finalizer.index("GITHUB_STEP_SUMMARY"))

    def test_gradle_diagnostics_are_not_left_in_the_allowlisted_log_directory(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for name in ("canary", "full-shard"):
            body = job_body(workflow, name)
            self.assertIn('raw_log="${RUNNER_TEMP}', body)
            self.assertIn('> "$raw_log" 2>&1', body)
            self.assertIn("BUILD SUCCESSFUL in", body)
            self.assertIn("BUILD FAILED in", body)
            self.assertIn('rm -f "$raw_log"', body)
            self.assertNotIn('> "$log_path" 2>&1', body)

    def test_emulator_script_does_not_share_local_variables_between_action_shells(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        canary = job_body(workflow, "canary")
        full_shard = job_body(workflow, "full-shard")

        self.assertNotIn('instrumentation_log="${RUNNER_TEMP}', canary)
        self.assertNotIn('instrumentation_log="${RUNNER_TEMP}', full_shard)
        self.assertNotIn('> "$instrumentation_log" 2>&1', canary)
        self.assertNotIn('> "$instrumentation_log" 2>&1', full_shard)
        self.assertIn(
            'bash private-source/tools/yuzono_anime_probe/android_harness/run_emulator_probes.sh > '
            '"${RUNNER_TEMP}/goanime-yuzono-canary-instrumentation/instrumentation.log" 2>&1',
            canary,
        )
        self.assertIn(
            'bash private-source/tools/yuzono_anime_probe/android_harness/run_emulator_probes.sh > '
            '"${RUNNER_TEMP}/goanime-yuzono-full-instrumentation-${{ matrix.shard }}/instrumentation.log" 2>&1',
            full_shard,
        )


class ContinuationRequestContractTest(unittest.TestCase):
    def test_orphan_continuation_dispatch_is_rejected_but_origin_bound_dispatch_is_accepted(self) -> None:
        valid = run_script(
            VALIDATE_CONTINUATION_SCRIPT,
            "--parent-run-id",
            "123",
            "--reference-runtime-run-id",
            "456",
            "--continuation-index",
            "1",
        )
        self.assertEqual(valid.returncode, 0, valid.stderr)

        orphan = run_script(
            VALIDATE_CONTINUATION_SCRIPT,
            "--parent-run-id",
            "",
            "--reference-runtime-run-id",
            "",
            "--continuation-index",
            "1",
        )
        self.assertNotEqual(orphan.returncode, 0)
        self.assertIn("continuation", (orphan.stderr + orphan.stdout).lower())


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

    def test_full_execution_requires_an_accepted_canary_on_the_same_runtime(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        canary = job_body(workflow, "canary")
        prepare_full = job_body(workflow, "prepare-full")
        full_shard = job_body(workflow, "full-shard")
        finalizer = job_body(workflow, "finalize-full")

        self.assertTrue(VERIFY_CANARY_SCRIPT.is_file(), "canary verifier is missing")
        self.assertIn("verify_canary.py", canary)
        self.assertIn("canary-verification.json", canary)
        self.assertIn("animefire,anikyuu,pifansubs", canary)
        self.assertIn("--structural-module", canary)
        self.assertIn("--candidate-modules", canary)
        self.assertRegex(canary, r"mode\s*!=\s*'deterministic'")
        self.assertIn("- canary", prepare_full)
        self.assertIn("needs.canary.result == 'success'", prepare_full)
        self.assertIn("- canary", full_shard)
        self.assertIn("needs.canary.result == 'success'", full_shard)
        self.assertIn("- canary", finalizer)
        self.assertIn("needs.canary.result == 'success'", finalizer)
        self.assertLess(canary.index("verify_canary.py"), canary.index("actions/upload-artifact@"))

    def test_canary_verifier_accepts_identity_bound_control_and_terminal_candidate(self) -> None:
        self.assertTrue(VERIFY_CANARY_SCRIPT.is_file(), "canary verifier is missing")
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            state = base / "probe-state"
            providers = state / "providers"
            checkpoints = state / "checkpoints"
            providers.mkdir(parents=True)
            checkpoints.mkdir()
            runtime = base / "reference-runtime"
            runtime.mkdir()
            app = runtime / "anikku-app-debug.apk"
            test_apk = runtime / "anikku-app-debug-androidTest.apk"
            app.write_bytes(b"app")
            test_apk.write_bytes(b"test")
            manifest = {
                "schemaVersion": 1,
                "goAnimeSourceSha": SOURCE_SHA,
                "anikkuSha": ANIKKU_SHA,
                "flexibleAdapterSha": FLEXIBLE_ADAPTER_SHA,
                "appApkSha256": hashlib.sha256(app.read_bytes()).hexdigest(),
                "testApkSha256": hashlib.sha256(test_apk.read_bytes()).hexdigest(),
                "jdkMajor": 17,
                "buildAttempt": 1,
                "fallbackUsed": False,
            }
            (runtime / "reference-runtime-manifest.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )

            def provider(module: str, *, ready: bool) -> dict[str, object]:
                return {
                    "sourceId": f"yuzono.pt.{module}",
                    "module": module,
                    "displayName": module,
                    "status": "ready" if ready else "partial",
                    "stage": "stream" if ready else "catalog",
                    "languageMode": "sub",
                    "titles": ["Synthetic title"],
                    "pagesVisited": 1,
                    "catalogueComplete": True,
                    "catalogueTermination": "natural-end",
                    "rawTitleCount": 1,
                    "distinctRawTitleCount": 1,
                    "playbackSampleCount": 1 if ready else 0,
                    "failureKind": None if ready else "media-unverified",
                    "schemaVersion": 3,
                    "executionIdentity": {
                        "extensionPackage": f"safe.{module}",
                        "extensionClass": f"safe.{module}.Source",
                        "extensionApkSha256": "a" * 64,
                    },
                    "sampleLineage": {
                        "catalogueDigest": "b" * 64,
                        "animeOrdinal": 0,
                        "animeLabelHash": "c" * 64,
                        "episodeOrdinal": 0,
                        "episodeLabelHash": "d" * 64,
                        "resolverMode": "direct",
                    } if ready else None,
                    "resolutionSampleCount": 1 if ready else 0,
                    "mediaEvidence": {
                        "transportObserved": ready,
                        "playerReadyObserved": ready,
                        "timeAdvancedObserved": ready,
                        "videoTrackObserved": ready,
                        "firstFrameObserved": ready,
                        "failureKind": None if ready else "media-unverified",
                    },
                }

            def checkpoint(module: str, *, status: str, playback: int) -> dict[str, object]:
                return {
                    "schemaVersion": 2,
                    "generationId": "canary-1",
                    "goAnimeSourceSha": SOURCE_SHA,
                    "goAnimeBaselineSha": "b" * 40,
                    "upstreamRevision": "c" * 40,
                    "anikkuRevision": ANIKKU_SHA,
                    "sourceId": f"yuzono.pt.{module}",
                    "stage": "classified",
                    "status": status,
                    "retryCount": 0,
                    "titleCount": 1,
                    "playbackSampleCount": playback,
                    "failureKind": None if status == "ready" else "media-unverified",
                }

            for module, ready in (
                ("animefire", False),
                ("anikyuu", True),
                ("pifansubs", False),
            ):
                (providers / f"{module}.json").write_text(
                    json.dumps(provider(module, ready=ready)), encoding="utf-8"
                )
                (checkpoints / f"{module}.json").write_text(
                    json.dumps(
                        checkpoint(
                            module,
                            status="ready" if ready else "pending",
                            playback=1 if ready else 0,
                        )
                    ),
                    encoding="utf-8",
                )

            output = base / "canary-verification" / "canary-verification.json"
            result = run_script(
                VERIFY_CANARY_SCRIPT,
                "--root",
                str(state),
                "--manifest",
                str(runtime / "reference-runtime-manifest.json"),
                "--modules",
                "animefire,anikyuu,pifansubs",
                "--structural-module",
                "animefire",
                "--candidate-modules",
                "anikyuu,pifansubs",
                "--generation-id",
                "canary-1",
                "--goanime-source-sha",
                SOURCE_SHA,
                "--goanime-baseline-sha",
                "b" * 40,
                "--upstream-revision",
                "c" * 40,
                "--anikku-sha",
                ANIKKU_SHA,
                "--output",
                str(output),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            verification = json.loads(output.read_text(encoding="utf-8"))
            self.assertTrue(verification["accepted"])
            self.assertEqual(verification["terminalMediaModules"], ["anikyuu"])
            self.assertEqual(verification["violations"], [])

            for module in ("anikyuu", "pifansubs"):
                (providers / f"{module}.json").write_text(
                    json.dumps(provider(module, ready=False)), encoding="utf-8"
                )
                (checkpoints / f"{module}.json").write_text(
                    json.dumps(checkpoint(module, status="pending", playback=0)),
                    encoding="utf-8",
                )
            no_media_output = base / "rejected-no-media" / "canary-verification.json"
            no_media = run_script(
                VERIFY_CANARY_SCRIPT,
                "--root",
                str(state),
                "--manifest",
                str(runtime / "reference-runtime-manifest.json"),
                "--modules",
                "animefire,anikyuu,pifansubs",
                "--structural-module",
                "animefire",
                "--candidate-modules",
                "anikyuu,pifansubs",
                "--generation-id",
                "canary-1",
                "--goanime-source-sha",
                SOURCE_SHA,
                "--goanime-baseline-sha",
                "b" * 40,
                "--upstream-revision",
                "c" * 40,
                "--anikku-sha",
                ANIKKU_SHA,
                "--output",
                str(no_media_output),
            )
            self.assertEqual(no_media.returncode, 1, no_media.stderr)
            no_media_verification = json.loads(no_media_output.read_text(encoding="utf-8"))
            self.assertFalse(no_media_verification["accepted"])
            self.assertIn("candidate provider lacks terminal media", no_media_verification["violations"])
            sanitized = run_script(
                SANITIZE_SCRIPT,
                "--root",
                str(output.parent),
            )
            self.assertEqual(sanitized.returncode, 0, sanitized.stderr)

            legacy_provider = json.loads((providers / "pifansubs.json").read_text(encoding="utf-8"))
            for field in (
                "schemaVersion",
                "executionIdentity",
                "sampleLineage",
                "resolutionSampleCount",
                "mediaEvidence",
            ):
                legacy_provider.pop(field)
            (providers / "pifansubs.json").write_text(
                json.dumps(legacy_provider), encoding="utf-8"
            )
            rejected_output = base / "rejected-canary-verification" / "canary-verification.json"
            rejected = run_script(
                VERIFY_CANARY_SCRIPT,
                "--root",
                str(state),
                "--manifest",
                str(runtime / "reference-runtime-manifest.json"),
                "--modules",
                "animefire,anikyuu,pifansubs",
                "--structural-module",
                "animefire",
                "--candidate-modules",
                "anikyuu,pifansubs",
                "--generation-id",
                "canary-1",
                "--goanime-source-sha",
                SOURCE_SHA,
                "--goanime-baseline-sha",
                "b" * 40,
                "--upstream-revision",
                "c" * 40,
                "--anikku-sha",
                ANIKKU_SHA,
                "--output",
                str(rejected_output),
            )
            self.assertEqual(rejected.returncode, 1, rejected.stderr)
            rejected_verification = json.loads(rejected_output.read_text(encoding="utf-8"))
            self.assertFalse(rejected_verification["accepted"])
            self.assertIn("path identity missing: pifansubs", rejected_verification["violations"])


if __name__ == "__main__":
    unittest.main()
