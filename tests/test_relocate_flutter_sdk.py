from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

from scripts.relocate_flutter_sdk import relocate_flutter_sdk


def resolve(value: str, config: Path) -> Path:
    parsed = urlparse(urljoin(config.resolve().as_uri(), value))
    return Path(unquote(parsed.path)).resolve()


class RelocateFlutterSdkTests(unittest.TestCase):
    def fixture(self, root: Path) -> tuple[Path, Path, Path, Path]:
        source_cache = root / "runner-cache"
        package = source_cache / "hosted" / "pub.dev" / "args-2.7.0"
        package.mkdir(parents=True)
        (package / "pubspec.yaml").write_text("name: args\n", encoding="utf-8")

        bundle = root / "bundle"
        flutter = bundle / "flutter"
        target_cache = bundle / "pub-cache"
        shutil.copytree(source_cache, target_cache)
        tools = flutter / "packages" / "flutter_tools"
        config = tools / ".dart_tool" / "package_config.json"
        config.parent.mkdir(parents=True)
        (tools / "pubspec.yaml").write_text("name: flutter_tools\n", encoding="utf-8")
        config.write_text(
            json.dumps(
                {
                    "configVersion": 2,
                    "packages": [
                        {
                            "name": "args",
                            "rootUri": package.resolve().as_uri(),
                            "packageUri": "lib/",
                            "languageVersion": "3.3",
                        },
                        {
                            "name": "flutter_tools",
                            "rootUri": "../",
                            "packageUri": "lib/",
                            "languageVersion": "3.10",
                        },
                    ],
                    "generator": "pub",
                    "flutterRoot": (root / "runner-flutter").resolve().as_uri(),
                    "pubCache": source_cache.resolve().as_uri(),
                }
            ),
            encoding="utf-8",
        )
        return bundle, flutter, target_cache, config

    def test_rewrites_metadata_and_survives_bundle_move(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle, flutter, pub_cache, config = self.fixture(root)
            result = relocate_flutter_sdk(flutter, pub_cache)
            self.assertEqual(result["relocated_absolute_packages"], 1)

            moved = root / "moved-bundle"
            bundle.rename(moved)
            moved_config = moved / config.relative_to(bundle)
            data = json.loads(moved_config.read_text(encoding="utf-8"))
            self.assertFalse(data["packages"][0]["rootUri"].startswith("file:"))
            self.assertFalse(data["flutterRoot"].startswith("file:"))
            self.assertFalse(data["pubCache"].startswith("file:"))
            for package in data["packages"]:
                self.assertTrue((resolve(package["rootUri"], moved_config) / "pubspec.yaml").is_file())
            self.assertEqual(resolve(data["flutterRoot"], moved_config), moved / "flutter")
            self.assertEqual(resolve(data["pubCache"], moved_config), moved / "pub-cache")

    def test_rejects_absolute_package_outside_source_cache(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, flutter, pub_cache, config = self.fixture(root)
            outside = root / "outside"
            outside.mkdir()
            (outside / "pubspec.yaml").write_text("name: outside\n", encoding="utf-8")
            data = json.loads(config.read_text(encoding="utf-8"))
            data["packages"][0]["rootUri"] = outside.resolve().as_uri()
            config.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "outside the source Pub cache"):
                relocate_flutter_sdk(flutter, pub_cache)

    def test_rejects_missing_relocated_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, flutter, pub_cache, _ = self.fixture(root)
            shutil.rmtree(pub_cache / "hosted" / "pub.dev" / "args-2.7.0")
            with self.assertRaisesRegex(ValueError, "missing pubspec"):
                relocate_flutter_sdk(flutter, pub_cache)


if __name__ == "__main__":
    unittest.main()
