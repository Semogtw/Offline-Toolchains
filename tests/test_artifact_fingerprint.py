import json, subprocess, sys, tempfile, unittest
from pathlib import Path
from scripts.artifact_fingerprint import set_fingerprint

ROOT=Path(__file__).resolve().parents[1]
class ArtifactFingerprintTests(unittest.TestCase):
    def test_cli_matches_library_and_changes_with_lock(self):
        first=set_fingerprint('jdk21','jdk21','not-applicable','0'*64,'abc',ROOT)
        second=set_fingerprint('jdk21','jdk21','not-applicable','1'*64,'abc',ROOT)
        self.assertNotEqual(first['set_fingerprint'],second['set_fingerprint'])
        result=subprocess.run([sys.executable,str(ROOT/'scripts/artifact_fingerprint.py'),'--profile','jdk21','--package','jdk21','--lock-mode','not-applicable','--lock-fingerprint','0'*64,'--workflow-commit','abc'],check=True,text=True,capture_output=True)
        self.assertEqual(first,json.loads(result.stdout))
if __name__=='__main__': unittest.main()
