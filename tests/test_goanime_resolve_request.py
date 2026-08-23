import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "goanime_resolve_request.py"
LEGACY_BRANCH = "feat/scrapling-provider-pipeline"


class GoAnimeResolveRequestTest(unittest.TestCase):
    def _run_dispatch(self, *args: str) -> dict[str, str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "github-output.txt"
            env = dict(os.environ)
            env["GITHUB_EVENT_NAME"] = "workflow_dispatch"
            env["GITHUB_OUTPUT"] = str(output)
            subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--request-dir",
                    "triggers/goanime-scrapling-provider-cache",
                    *args,
                ],
                cwd=ROOT,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            return dict(
                line.split("=", 1)
                for line in output.read_text(encoding="utf-8").splitlines()
                if "=" in line
            )

    def test_schedule_without_target_resolves_main(self) -> None:
        self.assertEqual(self._run_dispatch()["target_branch"], "main")

    def test_legacy_workflow_default_is_migrated_to_main(self) -> None:
        self.assertEqual(
            self._run_dispatch("--dispatch-target", LEGACY_BRANCH)["target_branch"],
            "main",
        )

    def test_explicit_nonlegacy_target_is_preserved(self) -> None:
        self.assertEqual(
            self._run_dispatch("--dispatch-target", "feature/provider-test")[
                "target_branch"
            ],
            "feature/provider-test",
        )


if __name__ == "__main__":
    unittest.main()
