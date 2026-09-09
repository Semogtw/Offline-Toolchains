import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "goanime-manga-global-cache.yml"
RUNNER = ROOT / "scripts" / "run_manga_checkpoint_budget_loop.sh"


class MangaGlobalCacheMultiUnitWorkflowTest(unittest.TestCase):
    def test_budget_runner_exists_and_is_wired_into_checkpoint_step(self):
        self.assertTrue(RUNNER.is_file(), "multi-unit checkpoint budget runner must exist")
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("CHECKPOINT_RUN_BUDGET_MINUTES: 300", workflow)
        self.assertIn("CHECKPOINT_MIN_UNIT_WINDOW_MINUTES: 30", workflow)
        self.assertIn("CHECKPOINT_STEP_TIMEOUT_MINUTES: 330", workflow)
        self.assertIn("run_manga_checkpoint_budget_loop.sh", workflow)
        self.assertNotIn('"${CHECKPOINT_UNIT_TIMEOUT_MINUTES}m"', workflow)

    def test_budget_runner_reuses_one_job_for_multiple_durable_units(self):
        runner = RUNNER.read_text(encoding="utf-8")
        required = [
            "while true",
            "CHECKPOINT_RUN_BUDGET_MINUTES",
            "CHECKPOINT_MIN_UNIT_WINDOW_MINUTES",
            "CHECKPOINT_WORKER",
            "GITHUB_OUTPUT=\"$unit_output\"",
            "CHECKPOINT_CONTINUE",
            "CHECKPOINT_COMPLETE",
            "units_completed",
        ]
        for token in required:
            self.assertIn(token, runner)


if __name__ == "__main__":
    unittest.main()
