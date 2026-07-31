from __future__ import annotations
import unittest
from pathlib import Path
from scripts.validate_toolchain_request import validate

class ToolchainRequestTests(unittest.TestCase):
    def test_aggregate_request_is_normalized(self):
        result=validate({'profile':'goanime-full','force_rebuild':False},Path('profiles'))
        self.assertEqual(result['project'],'goanime')
        self.assertEqual(result['concrete_profiles'],['android-base','goanime-analysis','goanime-android'])
    def test_unknown_and_extra_fields_are_rejected(self):
        with self.assertRaises(ValueError): validate({'profile':'unknown','force_rebuild':False},Path('profiles'))
        with self.assertRaises(ValueError): validate({'profile':'jdk21','force_rebuild':False,'repository':'x'},Path('profiles'))
    def test_boolean_is_strict(self):
        with self.assertRaises(ValueError): validate({'profile':'jdk21','force_rebuild':'false'},Path('profiles'))
if __name__=='__main__': unittest.main()
