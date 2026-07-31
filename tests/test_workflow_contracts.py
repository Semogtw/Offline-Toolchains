import tempfile, unittest
from pathlib import Path
from scripts.validate_workflows import validate
ROOT=Path(__file__).resolve().parents[1]
class WorkflowContractTests(unittest.TestCase):
    def test_repository_workflows_satisfy_contract(self):
        self.assertEqual(validate(ROOT/'.github/workflows'),[])
    def test_retention_and_secret_regressions_are_detected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            for name,title in {
                'build-android-base.yml':'Build Android base','build-jdk21.yml':'Build portable JDK 21','build-goanime.yml':'Build GoAnime toolchain','build-zapzap.yml':'Build ZapZap toolchain','build-exact-toolchain.yml':'Build exact private-lock toolchain','request-toolchain-build.yml':'Request exact toolchain build','report-toolchain-runs.yml':'Report toolchain runs'}.items():
                (root/name).write_text(f'name: {title}\nretention-days: 2\n')
            errors=validate(root)
            self.assertTrue(any('retention exceeds' in item for item in errors))
if __name__=='__main__': unittest.main()
