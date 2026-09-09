import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "goanime-manga-checkpoint-recovery.yml"


class MangaCheckpointRecoveryWorkflowTest(unittest.TestCase):
    def test_recovery_workflow_resumes_existing_generation_without_creating_one(self):
        self.assertTrue(WORKFLOW.is_file(), "checkpoint recovery workflow must exist")
        workflow = WORKFLOW.read_text(encoding="utf-8")

        required = [
            "workflow_dispatch:",
            "triggers/goanime-manga-checkpoint-recovery/*.request.json",
            "target_ref:",
            "checkpoint_branch:",
            "source_sha:",
            "superseded_run_id:",
            "goanime-manga-checkpoint-recovery-${{ steps.request.outputs.checkpoint_branch }}",
            "git fetch --force --no-tags origin",
            "git checkout --detach refs/remotes/origin/manga-global-cache-checkpoint",
            "run_manga_checkpoint_budget_loop.sh",
            "MANGA_CHECKPOINT_BRANCH: ${{ steps.request.outputs.checkpoint_branch }}",
            "MANGA_CHECKPOINT_SOURCE_SHA: ${{ steps.request.outputs.source_sha }}",
            "MANGA_CHECKPOINT_TARGET_BRANCH: ${{ steps.request.outputs.target_ref }}",
            "gh workflow run goanime-manga-checkpoint-recovery.yml",
        ]
        for token in required:
            self.assertIn(token, workflow)

        forbidden = [
            "git switch -c",
            "checkpoint_branch=\"ci/manga-global-cache-${source_sha:0:12}-${GITHUB_RUN_ID}\"",
            "git push origin HEAD:\"$checkpoint_branch\"",
        ]
        for token in forbidden:
            self.assertNotIn(token, workflow)

    def test_recovery_workflow_fail_closes_on_generation_identity_mismatch(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        required = [
            ".ci/manga-global-cache/state.json",
            "checkpointBranch",
            "sourceSha",
            "targetBranch",
            "Generation identity mismatch",
        ]
        for token in required:
            self.assertIn(token, workflow)

    def test_recovery_can_cancel_one_explicitly_superseded_stuck_run(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Superseded run id must be numeric", workflow)
        self.assertIn("actions/runs/$SUPERSEDED_RUN_ID/cancel", workflow)
        self.assertIn("--method POST", workflow)


if __name__ == "__main__":
    unittest.main()
