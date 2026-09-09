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

    def test_authorization_commit_is_request_only(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Migration request commit must contain exactly one added request and no other changes", workflow)
        self.assertIn("git diff-tree --no-commit-id --name-only -r HEAD^ HEAD", workflow)
        self.assertIn("--diff-filter=A", workflow)

    def test_schema_inventory_fails_closed_on_unknown_user_tables(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for internal_pattern in ("sqlite_*", "d1_*", "_cf_*"):
            self.assertIn(f"name NOT GLOB '{internal_pattern}'", workflow)
        self.assertNotIn("name IN ('snapshot_versions'", workflow)
        self.assertIn("Expected exactly one D1 database named", workflow)


if __name__ == "__main__":
    unittest.main()
