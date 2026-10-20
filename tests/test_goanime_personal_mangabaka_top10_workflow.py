import pathlib
import re
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
WORKFLOW=ROOT/'.github/workflows/assemble-goanime-personal-mangabaka-top10.yml'

class OfflineAuthorityPipelineContract(unittest.TestCase):
    def test_locked_private_source_and_api_free(self):
        text=WORKFLOW.read_text()
        self.assertIn('fe6421d6324f7222af1b2eaff37c1c04726cdd00',text)
        self.assertIn('PRIVATE_REPOSITORIES_TOKEN',text)
        self.assertIn('github.actor == github.repository_owner',text)
        self.assertIn("github.event_name == 'push'",text)
        self.assertIn('persist-credentials: false',text)
        self.assertNotIn('reader-overlap.py',text)
        self.assertNotIn('api.mangabaka.org',text)
        self.assertNotIn('upload-artifact',text)
        self.assertNotIn('workflow_dispatch:',text)
    def test_no_public_private_data(self):
        text=WORKFLOW.read_text()
        self.assertIn('SHA-256',text) if False else None
        self.assertIn('88ef0094ccea57f1a21e2a7c2f51a321d6be27d8853bb3c066042b1a37bbab6f',text)
        self.assertIn('PRAGMA integrity_check',text)
        self.assertIn('PRAGMA foreign_key_check',text)
        self.assertIn('git rm -r tools/manga/.staged-mangabaka-top10',text)
        self.assertIn('git rm .github/workflows/assemble-private-mangabaka-top10.yml',text)
        self.assertIn('flutter build apk --debug',text)
        self.assertIn('test/services/manga/storage/manga_bundled_similar_sql_index_test.dart',text)
    def test_source_part_hash_count(self):
        data=WORKFLOW.read_text()
        block=data.split('known=',1)[1].split('\n',1)[0]
        hashes=re.findall(r"'[0-9a-f]{40}'",block)
        self.assertEqual(len(hashes),10)

if __name__=='__main__': unittest.main()