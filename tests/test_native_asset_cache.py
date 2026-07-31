from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.native_asset_cache import capture_cache, prepare_project_cache


class NativeAssetCacheTests(unittest.TestCase):
    def test_capture_excludes_ephemeral_files_and_prepares_project(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "shared"
            completed = source / "sqlite3" / "build" / "download-abc"
            completed.mkdir(parents=True)
            (completed / "libsqlite3.so").write_bytes(b"portable-native-library")
            (completed / "libsqlite3.so.tmp").write_bytes(b"partial")
            (source / "sqlite3" / ".lock").write_text("absolute runner path", encoding="utf-8")
            portable = root / "portable"
            captured = capture_cache(source, portable)
            self.assertEqual(captured["files"], 1)
            self.assertTrue((portable / "sqlite3/build/download-abc/libsqlite3.so").is_file())
            self.assertFalse((portable / "sqlite3/.lock").exists())
            self.assertFalse((portable / "sqlite3/build/download-abc/libsqlite3.so.tmp").exists())

            project = root / "project"
            project.mkdir()
            (project / "pubspec.yaml").write_text("name: project\n", encoding="utf-8")
            prepared = prepare_project_cache(portable, project)
            self.assertEqual(prepared["files"], 1)
            self.assertEqual(
                (project / ".dart_tool/hooks_runner/shared/sqlite3/build/download-abc/libsqlite3.so").read_bytes(),
                b"portable-native-library",
            )

    def test_rejects_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "shared"
            source.mkdir()
            target = root / "target"
            target.write_text("secret", encoding="utf-8")
            (source / "linked").symlink_to(target)
            with self.assertRaisesRegex(ValueError, "symlinks"):
                capture_cache(source, root / "portable")

    def test_rejects_empty_or_non_project_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "shared"
            source.mkdir()
            with self.assertRaisesRegex(ValueError, "no completed files"):
                capture_cache(source, root / "portable")
            cache = root / "cache"
            cache.mkdir()
            (cache / "file").write_text("x", encoding="utf-8")
            project = root / "project"
            project.mkdir()
            with self.assertRaisesRegex(ValueError, "pubspec"):
                prepare_project_cache(cache, project)


if __name__ == "__main__":
    unittest.main()
