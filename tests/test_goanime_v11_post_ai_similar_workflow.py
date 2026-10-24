"""Manual, private-only, final-catalog MangaBaka workflow security gates."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
FILE=ROOT/".github/workflows/release-goanime-v11-post-ai-similar-candidate.yml"


class PostAiMangaBakaWorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow=FILE.read_text(encoding="utf-8")

    def test_manual_only_and_exact_commit(self):
        s=self.workflow
        self.assertIn("workflow_dispatch:",s)
        self.assertNotIn("schedule:",s)
        self.assertIn("pull_request:",s)
        self.assertIn("if: github.event_name == 'workflow_dispatch' && github.actor == github.repository_owner && inputs.final_catalog_confirmation == true",s)
        self.assertIn("goanime_commit:",s)
        self.assertIn("reviewed_run_dir:",s)
        self.assertIn("final_catalog_confirmation:",s)
        self.assertNotIn("rights_receipt:",s)
        self.assertIn('test "$(git -C goanime rev-parse HEAD)" = "$INPUT_SHA"',s)
        self.assertIn('git -C goanime merge-base --is-ancestor "$catalog_code_sha" "$INPUT_SHA"',s)

    def test_private_runner_no_public_plaintext(self):
        s=self.workflow
        self.assertIn("runs-on: [self-hosted, linux, x64, goanime-offline]",s)
        self.assertIn("persist-credentials: false",s)
        self.assertIn("PRIVATE_REPOSITORIES_TOKEN",s)
        self.assertNotIn("actions/upload-artifact",s)
        self.assertNotIn("git push",s)
        self.assertNotIn("gh release",s)

    def test_only_final_verified_sources_and_manual_dispatch(self):
        s=self.workflow
        self.assertIn("--reviewed-run",s)
        self.assertIn("confirm-final-catalog",s)
        self.assertIn("--seed-manifest",s)
        self.assertNotIn("--rights-receipt",s)
        self.assertIn("--rate-per-minute 60",s)
        self.assertIn("--dry-run",s)
        self.assertIn("post_ai_mangabaka_similar.py finalize",s)
        self.assertIn("if: github.event_name == 'workflow_dispatch' && github.actor == github.repository_owner && inputs.final_catalog_confirmation == true",s)
        self.assertIn("reader_overlap.sqlite",s)
        self.assertIn("timeout --signal=TERM",s)
        self.assertIn("timeout-minutes: 360",s)
        self.assertIn("timeout-minutes: 330",s)
        self.assertIn("300m",s)


if __name__=="__main__":
    unittest.main()
