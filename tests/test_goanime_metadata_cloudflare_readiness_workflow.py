import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "probe-goanime-metadata-cloudflare-readiness.yml"


class MetadataCloudflareReadinessWorkflowTest(unittest.TestCase):
    def test_probe_is_request_driven_and_read_only(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        required = [
            "name: Probe GoAnime metadata Cloudflare readiness",
            "triggers/goanime-metadata-cloudflare-readiness/*.request.json",
            "permissions:\n  contents: read",
            "CLOUDFLARE_ACCOUNT_ID",
            "CLOUDFLARE_API_TOKEN",
            "GOANIME_CATALOG_WRITE_TOKEN",
            "SELECT name FROM sqlite_master",
            "workers/scripts/${WORKER_NAME}/settings",
            "Probe mode: read-only",
        ]
        for token in required:
            self.assertIn(token, workflow)

        forbidden = [
            "wrangler deploy",
            "migrations apply",
            "d1 execute",
            "git push",
            "contents: write",
            "DELETE FROM",
            "DROP TABLE",
            "ALTER TABLE",
            "CREATE TABLE",
        ]
        for token in forbidden:
            self.assertNotIn(token, workflow)

    def test_probe_fails_closed_when_credentials_are_missing(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("steps.credentials.outputs.ready != 'true'", workflow)
        self.assertIn("Remote inspection skipped; no Cloudflare mutation was attempted.", workflow)
        self.assertIn("steps.credentials.outputs.ready == 'true'", workflow)


if __name__ == "__main__":
    unittest.main()
