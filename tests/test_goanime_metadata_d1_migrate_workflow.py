import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "goanime-metadata-d1-migrate.yml"


class MetadataD1MigrateWorkflowTest(unittest.TestCase):
    def test_workflow_is_request_driven_immutable_and_fail_closed(self):
        self.assertTrue(WORKFLOW.exists(), "D1 migration workflow must exist")
        workflow = WORKFLOW.read_text(encoding="utf-8")
        required = [
            "triggers/goanime-metadata-d1-migrate/*.request.json",
            "permissions:\n  contents: read",
            "feat/manga-a71-indexing-supervisor",
            "${{ secrets.CLOUDFLARE_API_TOKEN || secrets.CF_API_TOKEN }}",
            "${{ secrets.GOANIME_CATALOG_WRITE_TOKEN }}",
            "migrationBlobSha",
            "git hash-object",
            "git rev-parse HEAD",
            "git merge-base --is-ancestor",
            "legacy-6",
            "manga-8",
            "0002_manga_search.sql",
            "apply == true",
            "Verified all 8 required D1 tables",
        ]
        for token in required:
            self.assertIn(token, workflow)

    def test_workflow_never_provisions_or_deploys_unrelated_cloudflare_resources(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        forbidden = [
            "wrangler deploy",
            "workers/scripts/${WORKER_NAME}",
            "d1/database\" \"$create_body",
            "Create or reuse D1",
            "0001_search_index.sql",
            "contents: write",
            "git push",
        ]
        for token in forbidden:
            self.assertNotIn(token, workflow)

    def test_mutation_requires_explicit_apply_and_exact_legacy_schema(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("steps.request.outputs.apply == 'true'", workflow)
        self.assertIn("steps.inspect.outputs.schema == 'legacy-6'", workflow)
        self.assertIn("steps.inspect.outputs.schema == 'manga-8'", workflow)
        self.assertIn("refusing to mutate", workflow)


if __name__ == "__main__":
    unittest.main()
