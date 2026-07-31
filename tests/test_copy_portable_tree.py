from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.copy_portable_tree import copy_portable_tree


class CopyPortableTreeTests(unittest.TestCase):
    def test_follows_valid_links_and_ignores_dangling_links(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            (source / "payload.txt").write_text("portable\n", encoding="utf-8")
            (source / "valid-link.txt").symlink_to("payload.txt")
            (source / "dangling-link.txt").symlink_to("missing.txt")

            destination = root / "destination"
            copy_portable_tree(source, destination)

            self.assertEqual((destination / "payload.txt").read_text(), "portable\n")
            self.assertEqual((destination / "valid-link.txt").read_text(), "portable\n")
            self.assertFalse((destination / "valid-link.txt").is_symlink())
            self.assertFalse((destination / "dangling-link.txt").exists())


    def test_rejects_symbolic_link_cycles(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            source.mkdir()
            (source / "loop").symlink_to(source, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "cycle"):
                copy_portable_tree(source, Path(temp) / "destination")

    def test_rejects_existing_or_nested_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            source.mkdir()
            existing = Path(temp) / "existing"
            existing.mkdir()
            with self.assertRaisesRegex(ValueError, "already exists"):
                copy_portable_tree(source, existing)
            with self.assertRaisesRegex(ValueError, "must not be inside"):
                copy_portable_tree(source, source / "nested")


if __name__ == "__main__":
    unittest.main()
