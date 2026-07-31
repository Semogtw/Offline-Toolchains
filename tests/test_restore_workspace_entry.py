from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.restore_workspace_entry import prepare_restored_project_caches


class RestoreWorkspaceEntryTests(unittest.TestCase):
    def test_declared_native_cache_is_seeded_into_restored_project(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "checkout"
            project.mkdir()
            (project / "pubspec.yaml").write_text("name: project\n", encoding="utf-8")
            toolchain = root / ".checkout-toolchains" / "goanime-analysis-test"
            cache = toolchain / "native-assets-cache/hooks_runner-shared/sqlite3/build/download-test"
            cache.mkdir(parents=True)
            (cache / "libsqlite3.so").write_bytes(b"sqlite")
            (toolchain / ".artifact-set.json").write_text(
                json.dumps({
                    "profile": "goanime-analysis",
                    "project_cache": "native-assets-cache/hooks_runner-shared",
                }),
                encoding="utf-8",
            )

            prepared = prepare_restored_project_caches(project)
            self.assertEqual(prepared[0]["profile"], "goanime-analysis")
            self.assertEqual(
                (project / ".dart_tool/hooks_runner/shared/sqlite3/build/download-test/libsqlite3.so").read_bytes(),
                b"sqlite",
            )

    def test_ignores_toolchains_without_project_cache(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "checkout"
            project.mkdir()
            (project / "pubspec.yaml").write_text("name: project\n", encoding="utf-8")
            toolchain = root / ".checkout-toolchains" / "jdk21-test"
            toolchain.mkdir(parents=True)
            (toolchain / ".artifact-set.json").write_text(
                json.dumps({"profile": "jdk21"}), encoding="utf-8"
            )
            self.assertEqual(prepare_restored_project_caches(project), [])

    def test_rejects_unsafe_cache_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "checkout"
            project.mkdir()
            (project / "pubspec.yaml").write_text("name: project\n", encoding="utf-8")
            toolchain = root / ".checkout-toolchains" / "unsafe"
            toolchain.mkdir(parents=True)
            (toolchain / ".artifact-set.json").write_text(
                json.dumps({"profile": "unsafe", "project_cache": "../escape"}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "unsafe project cache"):
                prepare_restored_project_caches(project)


if __name__ == "__main__":
    unittest.main()
