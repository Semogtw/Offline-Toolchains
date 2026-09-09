import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "probe-goanime-manga-public-edge.yml"


class MangaPublicEdgeProbeWorkflowTest(unittest.TestCase):
    def test_probe_is_request_driven_read_only_and_pinned(self):
        self.assertTrue(WORKFLOW.exists(), "public Manga edge probe workflow must exist")
        workflow = WORKFLOW.read_text(encoding="utf-8")
        required = [
            "triggers/goanime-manga-public-edge/*.request.json",
            "permissions:\n  contents: read",
            "feat/manga-a71-indexing-supervisor",
            "e84e231ac7b5b8777a70732045e07cff8591713d",
            "${{ secrets.GOANIME_CATALOG_WRITE_TOKEN }}",
            "persist-credentials: false",
            "https://goanime-metadata-edge.arthurgva1602.workers.dev",
            "/v4/manga?q=berserk&limit=5&sfw=true",
            "/v4/manga/2/full",
            "edge:smoke",
            "--expect-origin a71",
            "--cache-check 0",
        ]
        for token in required:
            self.assertIn(token, workflow)

        forbidden = [
            "CLOUDFLARE_API_TOKEN",
            "CF_API_TOKEN",
            "wrangler deploy",
            "d1 execute",
            "d1 migrations apply",
            "contents: write",
            "git push",
        ]
        for token in forbidden:
            self.assertNotIn(token, workflow)

    def test_request_commit_must_be_isolated(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Public edge probe request commit must contain exactly one added request and no other changes", workflow)
        self.assertIn("git diff-tree --no-commit-id --name-only -r HEAD^ HEAD", workflow)
        self.assertIn("--diff-filter=A", workflow)

    def test_failure_diagnostics_are_logged_and_sanitized(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("tee -a \"$GITHUB_STEP_SUMMARY\"", workflow)
        self.assertIn("x-goanime-origin", workflow.lower())
        self.assertIn("x-goanime-fallback", workflow.lower())
        self.assertIn("x-goanime-edge-cache", workflow.lower())
        self.assertIn("--output /dev/null", workflow)
        self.assertNotIn("cat /tmp/goanime", workflow)

    def test_probe_validates_manga_payload_semantics(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Validate public Manga payload semantics", workflow)
        self.assertIn(".data | type == \"array\"", workflow)
        self.assertIn(".mal_id == 2", workflow)
        self.assertIn("ascii_downcase | contains(\"berserk\")", workflow)
        self.assertIn(".data.mal_id == 2", workflow)
        self.assertIn("x-goanime-fallback", workflow.lower())

    def test_semantic_failure_reports_only_compact_public_metadata(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("search-summary=", workflow)
        self.assertIn("full-summary=", workflow)
        self.assertIn("{mal_id, title, title_english}", workflow)
        self.assertIn("dataType", workflow)
        self.assertNotIn("jq -c '.' /tmp/goanime-manga", workflow)

    def test_semantic_probe_repeats_three_authoritative_rounds(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("for attempt in 1 2 3; do", workflow)
        self.assertIn("semantic-attempt=$attempt", workflow)
        self.assertIn("sleep 2", workflow)
        self.assertIn("Semantic Manga stability: PASS (3/3 rounds)", workflow)


if __name__ == "__main__":
    unittest.main()
