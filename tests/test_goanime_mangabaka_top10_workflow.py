"""Basic reviewed-source, secret, and output safety contract for a public runner."""
from pathlib import Path
import unittest

W=Path(__file__).resolve().parents[1]/'.github/workflows/build-goanime-mangabaka-top10.yml'

class SecurityContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s=W.read_text(encoding='utf-8')

    def test_private_access_is_gated_and_pinned(self):
        self.assertIn("github.event_name != 'pull_request' && github.actor == github.repository_owner",self.s)
        self.assertIn('ref: 2036ff98eb01029cef24caada410723af2e0587b',self.s)
        self.assertIn('ref: b550ad4d8617381ebc87c81fc6a56e5d800875b1',self.s)
        self.assertIn('secrets.PRIVATE_REPOSITORIES_TOKEN',self.s)
        self.assertIn('persist-credentials: false',self.s)
        self.assertIn('permissions:\n  contents: read',self.s)

    def test_executable_blobs_are_verified(self):
        for sha in ('25a970f766088f31c39fbe452c58e958afa0e356','3fff99e93cf94bb6d4d82537522c5ed655173634','e709d2fdfac1f78fdb2a7041df4435975ec66913'):
            self.assertIn(sha,self.s)
        self.assertIn('Run all focused offline Python tests',self.s)

    def test_only_encrypted_artifact_is_uploaded(self):
        self.assertIn('GPG', self.s.upper())
        self.assertIn('2DE29DC31427CF0A911AB96175679291435059B0',self.s)
        self.assertIn('--encrypt "$work/package.tar.zst"',self.s)
        self.assertIn('path: ${{ runner.temp }}/goanime-mangabaka-top10/transfer/',self.s)
        self.assertIn('retention-days: 1',self.s)
        self.assertIn('if: always()',self.s)
        self.assertIn('rm -rf "$GITHUB_WORKSPACE/private-source"',self.s)

    def test_fail_closed_and_bound_ranking(self):
        self.assertIn('timeout --signal=TERM',self.s)
        self.assertIn('--rate-per-minute 120',self.s)
        self.assertIn('--min-mangabaka-roots 2000',self.s)
        self.assertIn("if largest is None or largest>10",self.s)
        self.assertIn('staging-only; requires redistribution and attribution review',self.s)

if __name__=='__main__': unittest.main()