"""Contracts for the public GoAnime MangaBaka reader-overlap workflow.

These tests are intentionally dependency-free so a PR can validate its
security gates without accessing the private GoAnime repository.
"""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/collect-goanime-mangabaka-reader-overlap.yml"


class ReaderOverlapWorkflowContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = WORKFLOW.read_text(encoding="utf-8")

    def test_has_public_pr_checks_and_explicit_collection_trigger(self):
        self.assertIn("pull_request:", self.source)
        self.assertIn("workflow_dispatch:", self.source)
        self.assertIn("triggers/goanime-mangabaka-reader-overlap/*.request", self.source)
        self.assertIn("github.event_name != 'pull_request'", self.source)

    def test_private_checkout_has_no_persisted_credentials(self):
        self.assertIn("repository: Semogtw/goanime-mobile", self.source)
        self.assertIn("persist-credentials: false", self.source)
        self.assertIn("token: ${{ secrets.PRIVATE_REPOSITORIES_TOKEN }}", self.source)
        self.assertIn("fetch-depth: 1", self.source)

    def test_run_is_bounded_and_validates_real_payload_first(self):
        self.assertIn("timeout-minutes: 330", self.source)
        self.assertIn("test_collect_mangabaka_reader_overlap.py", self.source)
        self.assertIn("--dry-run", self.source)
        self.assertIn("--max-requests 3", self.source)
        self.assertIn("--rate-per-minute 120", self.source)
        self.assertIn("parse_status='unrecognized'", self.source)

    def test_release_artifact_is_ciphertext_only_and_restored_on_failure(self):
        self.assertIn("gpg --batch --import", self.source)
        self.assertIn("gpg --batch --yes --trust-model always", self.source)
        self.assertIn("actions/upload-artifact@", self.source)
        self.assertIn("if: always()", self.source)
        self.assertIn("*.tar.zst.gpg", self.source)
        self.assertIn("retention-days: 7", self.source)
        self.assertNotIn("path: ${{ runner.temp }}/goanime-mangabaka-reader-overlap", self.source)

    def test_does_not_modify_the_private_catalog(self):
        self.assertNotIn("git push", self.source)
        self.assertNotIn("gh release", self.source)
        self.assertIn("catalog-db", self.source)
        self.assertIn("reader_overlap.sqlite", self.source)


if __name__ == "__main__":
    unittest.main()
