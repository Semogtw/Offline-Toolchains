from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class GoAnimeFranchiseRuntimeRefreshContractTest(unittest.TestCase):
    def test_global_finalizer_rebuilds_franchise_before_manifest(self) -> None:
        workflow = (
            ROOT / ".github/workflows/goanime-global-catalog-finalize.yml"
        ).read_text(encoding="utf-8")

        ordered_steps = [
            "Map promoted anime titles to MAL incrementally",
            "Capture MAL IDs requiring franchise refresh",
            "Rebuild franchise runtime artifacts for promoted anime",
            "Build title availability SQLite",
            "Build runtime database manifest",
        ]
        positions = [workflow.index(step) for step in ordered_steps]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("tools/build_franchise_availability_cache.dart", workflow)
        self.assertIn(
            "tools/postprocess_franchise_availability_cache.dart --write",
            workflow,
        )
        self.assertIn("tools/build_franchise_runtime_artifacts.dart", workflow)
        self.assertIn("current_ids - indexed_ids", workflow)

    def test_global_finalizer_validates_manifest_hashes_and_publish_order(self) -> None:
        workflow = (
            ROOT / ".github/workflows/goanime-global-catalog-finalize.yml"
        ).read_text(encoding="utf-8")
        validation = workflow[workflow.index("Validate runtime publication outputs") :]
        self.assertIn("franchise_availability.db.sha256", validation)
        self.assertIn("franchise_expected", validation)
        self.assertIn("dist/runtime_database_cache/franchise_availability.db", validation)

        publish = workflow[workflow.index("Publish runtime databases to R2") :]
        payload = publish.index("latest/franchise_availability.db")
        manifest = publish.index("latest/runtime_database_manifest.json")
        self.assertLess(payload, manifest)

    def test_global_finalizer_allows_rate_limited_mal_mapping_to_finish(self) -> None:
        workflow = (
            ROOT / ".github/workflows/goanime-global-catalog-finalize.yml"
        ).read_text(encoding="utf-8")
        match = re.search(
            r"jobs:\s+finalize:\s+.*?timeout-minutes:\s*(\d+)",
            workflow,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        self.assertGreaterEqual(int(match.group(1)), 180)

    def test_global_finalizer_wires_optional_private_jikan_origin(self) -> None:
        workflow = (
            ROOT / ".github/workflows/goanime-global-catalog-finalize.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("Validate optional private Jikan origin override", workflow)
        self.assertIn(
            "GOANIME_JIKAN_BASE_URL: ${{ secrets.GOANIME_JIKAN_BASE_URL }}",
            workflow,
        )
        self.assertIn(
            "GOANIME_METADATA_API_TOKEN: ${{ secrets.GOANIME_METADATA_API_TOKEN }}",
            workflow,
        )
        self.assertGreaterEqual(
            workflow.count("GOANIME_REQUIRE_PRIVATE_METADATA: 'true'"),
            2,
        )
        self.assertIn("GOANIME_JIKAN_BASE_URL is required", workflow)
        self.assertIn("GOANIME_METADATA_API_TOKEN is required", workflow)
        self.assertIn('from urllib.parse import urlsplit', workflow)
        self.assertIn('segments[-1] != "v4"', workflow)
        self.assertIn('parsed.scheme != "https"', workflow)

    def test_other_anime_refreshes_postprocess_incremental_graph(self) -> None:
        workflow = (
            ROOT / ".github/workflows/refresh-private-goanime-catalog.yml"
        ).read_text(encoding="utf-8")
        build = workflow.index("tools/build_franchise_availability_cache.dart")
        postprocess = workflow.index(
            "tools/postprocess_franchise_availability_cache.dart --write"
        )
        runtime = workflow.index("tools/build_franchise_runtime_artifacts.dart")
        self.assertLess(build, postprocess)
        self.assertLess(postprocess, runtime)


if __name__ == "__main__":
    unittest.main()
