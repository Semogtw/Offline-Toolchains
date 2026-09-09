import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "verify-goanime-manga-a71-d1.yml"


class GoAnimeMangaA71D1VerifyWorkflowTest(unittest.TestCase):
    def test_verifier_runs_only_from_toolchains_trigger(self):
        self.assertTrue(WORKFLOW.is_file(), "verification workflow must exist")
        workflow = WORKFLOW.read_text(encoding="utf-8")
        required = [
            "name: Verify GoAnime Manga A71 D1",
            "triggers/goanime-manga-a71-d1-verify/*.request.json",
            "repository: ${{ env.GOANIME_REPOSITORY }}",
            "Semogtw/goanime-mobile",
            "GOANIME_CATALOG_WRITE_TOKEN",
            "persist-credentials: false",
            "npm --prefix cloudflare/metadata-worker run repository:verify",
            "git diff --check \"$BASE_SHA..$SOURCE_SHA\" -- .",
            "check_markdown_diff_whitespace.py",
            "Actions executed only in `Semogtw/Offline-Toolchains`.",
        ]
        for token in required:
            self.assertIn(token, workflow)

        forbidden = [
            "git push origin",
            "gh workflow run",
            "workflow_dispatch:",
            "persist-credentials: true",
        ]
        for token in forbidden:
            self.assertNotIn(token, workflow)

    def test_verifier_binds_branch_sha_and_base_identity(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        required = [
            "EXPECTED_SOURCE_BRANCH: feat/manga-a71-indexing-supervisor",
            ".sourceBranch",
            ".sourceSha",
            ".baseSha",
            "Requested branch moved before verification.",
            "git merge-base --is-ancestor \"$BASE_SHA\" \"$SOURCE_SHA\"",
            "git cat-file -e \"${BASE_SHA}^{commit}\"",
        ]
        for token in required:
            self.assertIn(token, workflow)

    def test_verifier_is_read_only_against_goanime(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("permissions:\n  contents: read", workflow)
        self.assertNotIn("contents: write", workflow)
        self.assertNotIn("pull-requests: write", workflow)
        self.assertNotIn("actions: write", workflow)
        self.assertNotIn("git commit", workflow)
        self.assertNotIn("git cherry-pick", workflow)

    def test_markdown_hard_breaks_are_checked_separately(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("':(exclude,glob)*.md'", workflow)
        self.assertIn("':(exclude,glob)**/*.md'", workflow)
        self.assertIn("git diff --unified=0 --no-color", workflow)
        self.assertIn("python3 \"$GITHUB_WORKSPACE/scripts/check_markdown_diff_whitespace.py\"", workflow)


if __name__ == "__main__":
    unittest.main()
