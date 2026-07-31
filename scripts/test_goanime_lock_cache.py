import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts' / 'goanime_lock_cache.py'


class GoAnimeLockCacheTest(unittest.TestCase):
    def run_script(self, *args, check=True):
        return subprocess.run(
            ['python3', str(SCRIPT), *map(str, args)],
            text=True,
            capture_output=True,
            check=check,
        )

    def test_extracts_only_hosted_packages_without_private_metadata(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            lock = td / 'pubspec.lock'
            lock.write_text(
                'packages:\n'
                '  alpha:\n'
                '    dependency: direct main\n'
                '    description:\n'
                '      name: alpha\n'
                '      sha256: deadbeef\n'
                '      url: "https://pub.dev"\n'
                '    source: hosted\n'
                '    version: "1.2.3"\n'
                '  local_pkg:\n'
                '    dependency: direct main\n'
                '    description:\n'
                '      path: packages/local_pkg\n'
                '      relative: true\n'
                '    source: path\n'
                '    version: "0.0.1"\n'
                '  sdk_pkg:\n'
                '    dependency: direct main\n'
                '    description: flutter\n'
                '    source: sdk\n'
                '    version: "0.0.0"\n'
                'sdks:\n'
                '  dart: ">=3.10.0 <4.0.0"\n'
            )
            output = td / 'hosted-lock.json'
            self.run_script(
                'extract-lock', '--lockfile', lock, '--output', output,
                '--flutter-version', '3.44.1', '--dart-version', '3.12.1',
            )
            data = json.loads(output.read_text())
            self.assertEqual(data['packages'], {'alpha': '1.2.3'})
            self.assertEqual(data['package_count'], 1)
            serialized = output.read_text()
            self.assertNotIn('pub.dev', serialized)
            self.assertNotIn('local_pkg', serialized)
            self.assertNotIn('packages/local_pkg', serialized)

    def test_writes_exact_dependency_fixture(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            manifest = td / 'hosted-lock.json'
            manifest.write_text(json.dumps({
                'schema_version': 1,
                'flutter_version': '3.44.1',
                'dart_version': '3.12.1',
                'package_count': 2,
                'packages': {'alpha': '1.2.3', 'beta_pkg': '2.0.0+1'},
            }))
            output = td / 'pubspec.yaml'
            self.run_script(
                'write-pubspec', '--manifest', manifest, '--output', output,
            )
            text = output.read_text()
            self.assertIn('flutter:\n    sdk: flutter', text)
            self.assertIn('  alpha: "1.2.3"', text)
            self.assertIn('  beta_pkg: "2.0.0+1"', text)
            self.assertNotIn('flutter_test:', text)

    def test_verify_cache_reports_every_missing_package(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            manifest = td / 'hosted-lock.json'
            manifest.write_text(json.dumps({
                'schema_version': 1,
                'flutter_version': '3.44.1',
                'dart_version': '3.12.1',
                'package_count': 2,
                'packages': {'alpha': '1.2.3', 'beta_pkg': '2.0.0'},
            }))
            cache = td / 'cache'
            (cache / 'hosted' / 'pub.dev' / 'alpha-1.2.3').mkdir(parents=True)
            result = self.run_script(
                'verify-cache', '--manifest', manifest, '--pub-cache', cache,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('beta_pkg=2.0.0', result.stderr)
            self.assertNotIn('alpha=1.2.3', result.stderr)


if __name__ == '__main__':
    unittest.main()
