from __future__ import annotations
import tempfile, unittest
from pathlib import Path
from scripts.collect_lock_inputs import collect

class LockInputTests(unittest.TestCase):
    def test_goanime_fingerprint_changes_and_inventory_is_hosted(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'pubspec.yaml').write_text('name: sample\n')
            lock=root/'pubspec.lock'
            lock.write_text('''packages:\n  http:\n    dependency: direct main\n    description:\n      name: http\n      url: https://pub.dev\n    source: hosted\n    version: "1.2.0"\n''')
            first=collect(root,'goanime-analysis',Path('profiles'),'goanime')
            self.assertEqual(first['software'][0]['name'],'http')
            lock.write_text(lock.read_text().replace('1.2.0','1.3.0'))
            second=collect(root,'goanime-analysis',Path('profiles'),'goanime')
            self.assertNotEqual(first['lock_fingerprint'],second['lock_fingerprint'])
    def test_symlink_lock_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); target=root/'real'; target.write_text('x')
            (root/'pubspec.yaml').symlink_to(target); (root/'pubspec.lock').write_text('packages: {}\n')
            with self.assertRaisesRegex(ValueError,'symlink'): collect(root,'goanime-analysis',Path('profiles'),'goanime')
    def test_zapzap_catalog_and_cargo_are_inventoried(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); (root/'gradle').mkdir()
            (root/'gradle/wrapper').mkdir(); (root/'gradle/wrapper/gradle-wrapper.properties').write_text('distributionUrl=x\n')
            (root/'settings.gradle.kts').write_text('rootProject.name="x"\n')
            (root/'build.gradle.kts').write_text('dependencies { implementation("com.squareup.okhttp3:okhttp:4.12.0") }\n')
            (root/'gradle/libs.versions.toml').write_text('''[versions]\nkotlin="2.0.21"\n[plugins]\nkotlin={ id="org.jetbrains.kotlin.android", version.ref="kotlin" }\n''')
            result=collect(root,'zapzap-pure',Path('profiles'),'zapzap')
            names={item['name'] for item in result['software']}
            self.assertIn('com.squareup.okhttp3:okhttp',names)
            self.assertIn('org.jetbrains.kotlin.android',names)
if __name__=='__main__': unittest.main()
