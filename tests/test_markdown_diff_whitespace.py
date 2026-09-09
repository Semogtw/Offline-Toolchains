import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "check_markdown_diff_whitespace.py"
SPEC = importlib.util.spec_from_file_location("markdown_diff_whitespace", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class MarkdownDiffWhitespaceTest(unittest.TestCase):
    def test_allows_exact_markdown_hard_break(self):
        diff = [
            "diff --git a/docs/x.md b/docs/x.md\n",
            "+++ b/docs/x.md\n",
            "@@ -1,0 +1,2 @@\n",
            "+**Updated:** 2026-09-09  \n",
            "+plain line\n",
        ]
        self.assertEqual(MODULE.violations(diff), [])

    def test_rejects_other_trailing_whitespace(self):
        for suffix in [" ", "   ", "\t", " \t"]:
            with self.subTest(suffix=repr(suffix)):
                diff = [
                    "+++ b/docs/x.md\n",
                    "@@ -1,0 +1 @@\n",
                    f"+bad{suffix}\n",
                ]
                failures = MODULE.violations(diff)
                self.assertEqual(len(failures), 1)
                self.assertIn("docs/x.md:1", failures[0])

    def test_tracks_added_line_numbers_across_context(self):
        diff = [
            "+++ b/docs/x.md\n",
            "@@ -4,2 +4,3 @@\n",
            " context\n",
            "+ok  \n",
            "+bad \n",
            " context\n",
        ]
        self.assertEqual(len(MODULE.violations(diff)), 1)
        self.assertIn("docs/x.md:6", MODULE.violations(diff)[0])


if __name__ == "__main__":
    unittest.main()
