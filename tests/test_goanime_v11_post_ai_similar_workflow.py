"""Manual GitHub-hosted V11 final-catalog Similar Works security gates."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
FILE = ROOT / ".github/workflows/release-goanime-v11-post-ai-similar-candidate.yml"


class PostAiMangaBakaWorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = FILE.read_text(encoding="utf-8")

    def test_manual_owner_dispatch_and_exact_private_inputs(self):
        text = self.workflow
        self.assertIn("workflow_dispatch:", text)
        self.assertNotIn("schedule:", text)
        self.assertIn("pull_request:", text)
        self.assertIn(
            "if: github.event_name == 'workflow_dispatch' && github.actor == github.repository_owner && inputs.final_catalog_confirmation == true",
            text,
        )
        self.assertIn("goanime_commit:", text)
        self.assertIn("catalog_input_commit:", text)
        self.assertIn("catalog_package_sha256:", text)
        self.assertIn("final_catalog_confirmation:", text)
        self.assertNotIn("reviewed_run_dir:", text)
        self.assertNotIn("rights_receipt:", text)
        self.assertIn('test "$(git -C goanime rev-parse HEAD)" = "$INPUT_SHA"', text)
        self.assertIn('test "$(git -C catalog-input rev-parse HEAD)" = "$INPUT_CATALOG_COMMIT"', text)
        self.assertIn('git -C goanime merge-base --is-ancestor "$catalog_code_sha" "$INPUT_SHA"', text)
        self.assertIn("candidatePackageSha256", text)

    def test_uses_github_hosted_and_only_encrypted_artifact_handoffs(self):
        text = self.workflow
        self.assertIn("runs-on: ubuntu-24.04", text)
        self.assertNotIn("self-hosted", text)
        self.assertIn("persist-credentials: false", text)
        self.assertIn("PRIVATE_REPOSITORIES_TOKEN", text)
        self.assertIn("actions/upload-artifact@v4", text)
        self.assertIn("final-candidate.tar.zst.gpg", text)
        self.assertIn("checkpoint.tar.zst.gpg", text)
        self.assertIn("retention-days: 1", text)
        self.assertNotIn("gh release", text)

    def test_final_catalog_scope_rate_progress_and_timeouts(self):
        text = self.workflow
        self.assertIn("confirm-final-catalog", text)
        self.assertIn("--reviewed-run", text)
        self.assertIn("--seed-manifest", text)
        self.assertIn("--dry-run", text)
        self.assertIn("post_ai_mangabaka_similar.py finalize", text)
        self.assertIn("--rate-per-minute 60", text)
        self.assertIn("--report-every 534", text)
        self.assertIn("timeout --signal=TERM", text)
        self.assertIn("timeout-minutes: 360", text)
        self.assertIn("timeout-minutes: 330", text)
        self.assertIn("300m", text)
        self.assertIn("github.actor == github.repository_owner", text)


if __name__ == "__main__":
    unittest.main()
