"""Tests for the stable release window gate in promote-testing-to-main.yml.

`:stable` is meant to promote on Tuesdays only (bluefin#1066). The gate that
enforces that is a shell step whose output decides whether the promotion PR is
enqueued for merge, and it shipped with no coverage -- so nothing catches a
typo that moves the release day or opens the gate on every run.

The step is extracted from the workflow and executed here against a stubbed
`date`, so these tests exercise the real shell rather than asserting on its
text.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


WORKFLOW = (
    Path(__file__).parents[1] / ".github" / "workflows" / "promote-testing-to-main.yml"
)
GATE_WORKFLOW = (
    Path(__file__).parents[1] / ".github" / "workflows" / "check-release-window.yml"
)
POST_TESTING_WORKFLOW = (
    Path(__file__).parents[1] / ".github" / "workflows" / "post-testing-e2e.yml"
)
EXECUTE_WORKFLOW = (
    Path(__file__).parents[1] / ".github" / "workflows" / "execute-release.yml"
)
BUILD_WORKFLOW = (
    Path(__file__).parents[1] / ".github" / "workflows" / "build-image-testing.yml"
)
EXECUTE_STEP = "      - id: check\n"
STEP = "      - name: Determine whether to enqueue the promotion\n"

# Stands in for `date`: records the arguments it was called with, and answers a
# weekday request from GH_STUB_WEEKDAY. Anything else falls through to the real
# binary so the step is not silently reshaped by the stub.
STUB_DATE = '''#!/usr/bin/env python3
import os
import subprocess
import sys

arguments = sys.argv[1:]
with open(os.environ["GH_STUB_DATE_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(arguments) + "\\n")

if any(argument.startswith("+%") for argument in arguments):
    print(os.environ["GH_STUB_WEEKDAY"])
    sys.exit(0)


sys.exit(subprocess.run(["/usr/bin/date", *arguments], check=False).returncode)
'''

TUESDAY = "2"
# ISO 8601 weekdays, as `date +%u` reports them: Monday is 1, Sunday is 7.
ALL_WEEKDAYS = ("1", "2", "3", "4", "5", "6", "7")


def window_script() -> str:
    """Return the shell body of the release-window step."""
    workflow = GATE_WORKFLOW.read_text(encoding="utf-8")
    if STEP not in workflow:
        raise AssertionError(f"{GATE_WORKFLOW.name} has no {STEP.strip()!r} step")
    body = workflow.split(STEP, 1)[1].split("        run: |\n", 1)[1]
    lines: list[str] = []
    for line in body.splitlines():
        # The step ends at the first non-blank line that leaves the run block.
        if line.strip() and not line.startswith(" " * 10):
            break
        lines.append(line)
    return textwrap.dedent("\n".join(lines))

def execute_trigger_script() -> str:
    """Return the shipped execute-release trigger shell body."""
    workflow = EXECUTE_WORKFLOW.read_text(encoding="utf-8")
    body = workflow.split(EXECUTE_STEP, 1)[1].split("        run: |\n", 1)[1]
    lines: list[str] = []
    for line in body.splitlines():
        if line.strip() and not line.startswith(" " * 10):
            break
        lines.append(line)
    return textwrap.dedent("\n".join(lines))


class ReleaseWindowTests(unittest.TestCase):
    def run_window(self, event: str, weekday: str = TUESDAY) -> tuple[str, list[str]]:
        """Run the gate for `event` on `weekday`; return its decision and date calls."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            stub = root / "date"
            stub.write_text(STUB_DATE, encoding="utf-8")
            stub.chmod(0o755)
            date_log = root / "date-calls.log"
            date_log.touch()
            step_output = root / "github-output"
            step_output.touch()

            environment = dict(os.environ)
            environment.update(
                PATH=f"{root}{os.pathsep}{environment['PATH']}",
                EVENT_NAME=event,
                GITHUB_OUTPUT=str(step_output),
                GH_STUB_WEEKDAY=weekday,
                GH_STUB_DATE_LOG=str(date_log),
            )

            result = subprocess.run(
                ["bash", "-c", window_script()],
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

            written = step_output.read_text(encoding="utf-8").split()
            decisions = [
                line.split("=", 1)[1]
                for line in written
                if line.startswith("should_enqueue=")
            ]
            self.assertEqual(len(decisions), 1, written)
            calls = date_log.read_text(encoding="utf-8").splitlines()
            return decisions[0], calls

    def test_scheduled_run_enqueues_only_on_tuesday(self) -> None:
        # The whole point of bluefin#1066: a daily cron, but only Tuesday
        # releases. Every other day must refresh the PR without enqueueing it.
        for weekday in ALL_WEEKDAYS:
            with self.subTest(weekday=weekday):
                decision, _ = self.run_window("schedule", weekday)
                self.assertEqual(decision, "true" if weekday == TUESDAY else "false")

    def test_successful_e2e_completion_enqueues_only_on_tuesday(self) -> None:
        for weekday in ALL_WEEKDAYS:
            with self.subTest(weekday=weekday):
                decision, _ = self.run_window("workflow_run", weekday)
                self.assertEqual(decision, "true" if weekday == TUESDAY else "false")

    def test_manual_dispatch_is_the_hotfix_escape_hatch(self) -> None:
        # workflow_dispatch is the documented out-of-band release path, so it
        # must not be subject to the weekday gate.
        for weekday in ALL_WEEKDAYS:
            with self.subTest(weekday=weekday):
                decision, _ = self.run_window("workflow_dispatch", weekday)
                self.assertEqual(decision, "true")

    def test_push_to_testing_never_releases(self) -> None:
        # Pushes keep the promotion PR fresh; they must never cut a release,
        # not even on a Tuesday.
        for weekday in (TUESDAY, "5"):
            with self.subTest(weekday=weekday):
                decision, _ = self.run_window("push", weekday)
                self.assertEqual(decision, "false")

    def test_release_day_is_read_as_an_iso_weekday_in_utc(self) -> None:
        # `date -u +%u` is load-bearing twice over. Without -u the release day
        # follows the runner's clock rather than the UTC window the schedule is
        # written in, and %u (Mon=1..Sun=7) is what makes the literal "2" mean
        # Tuesday -- the sibling repos gate on Thursday and Sunday with this
        # same pattern, where %u and %w disagree.
        _, calls = self.run_window("schedule")
        self.assertEqual(len(calls), 1, calls)
        self.assertIn("-u", calls[0].split())
        self.assertIn("+%u", calls[0].split())

    def test_unknown_events_do_not_release(self) -> None:
        # The gate must fail closed: anything not explicitly allowed above is a
        # refresh, not a release.
        decision, _ = self.run_window("repository_dispatch", TUESDAY)
        self.assertEqual(decision, "false")


class ExecuteReleaseTriggerTests(unittest.TestCase):
    def run_trigger(self, event: str, commit_message: str) -> str:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "github-output"
            output.touch()
            environment = dict(os.environ)
            environment.update(
                COMMIT_MSG=commit_message,
                EVENT=event,
                GITHUB_OUTPUT=str(output),
            )
            result = subprocess.run(
                ["bash", "-c", execute_trigger_script()],
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return output.read_text(encoding="utf-8").strip()

    def test_generated_promotion_commit_executes_release(self) -> None:
        output = self.run_trigger(
            "push", "ci(promote): bluefin testing → main 2026-09-17 (#1233)"
        )
        self.assertEqual(output, "is-promotion=true")

    def test_legacy_promotion_commit_executes_release(self) -> None:
        output = self.run_trigger("push", "chore: promote testing to main")
        self.assertEqual(output, "is-promotion=true")

    def test_ordinary_main_push_does_not_execute_release(self) -> None:
        output = self.run_trigger("push", "fix: unrelated main change")
        self.assertEqual(output, "is-promotion=false")

    def test_manual_dispatch_remains_release_escape_hatch(self) -> None:
        output = self.run_trigger("workflow_dispatch", "")
        self.assertEqual(output, "is-promotion=true")


class ReleaseWindowWiringTests(unittest.TestCase):
    """The gate is only a gate while the promote job actually consults it."""

    def test_release_window_controls_queue_enrolment(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        wiring = [
            line
            for line in workflow.splitlines()
            if line.strip().startswith("enqueue_promotion:")
        ]
        self.assertEqual(len(wiring), 1, workflow)
        self.assertIn("needs.release_window.outputs.should_enqueue", wiring[0])

    def test_release_uses_merge_queue_after_e2e_without_reviewers(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("use_merge_queue: true", workflow)
        self.assertIn("run_e2e: true", workflow)
        self.assertIn("e2e_suites: smoke,common", workflow)
        self.assertIn("e2e_image: ghcr.io/projectbluefin/bluefin:testing", workflow)
        self.assertIn("e2e_status_context: e2e/post-testing", workflow)
        self.assertIn("request_reviewer: false", workflow)

    def test_caller_invokes_release_window_workflow(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("uses: ./.github/workflows/check-release-window.yml", workflow)

    def test_e2e_completion_retriggers_promotion(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('workflows: ["Post-Testing E2E"]', workflow)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", workflow)

    def test_every_testing_push_builds_release_candidates(self) -> None:
        workflow = BUILD_WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn("paths-ignore:", workflow)

    def test_release_window_publishes_the_decision(self) -> None:
        workflow = GATE_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("should_enqueue: ${{ steps.window.outputs.should_enqueue }}", workflow)
        self.assertIn("value: ${{ jobs.release_window.outputs.should_enqueue }}", workflow)

    def test_execute_release_consumes_producer_evidence_once(self) -> None:
        workflow = EXECUTE_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("run_release_gate: false", workflow)
        self.assertIn("source_branch: testing", workflow)
        self.assertNotIn("gate_suites:", workflow)

class E2EQualificationWiringTests(unittest.TestCase):
    """The source commit and mutable tag must represent the same tested image."""

    def test_testing_build_promotes_both_tested_variants_and_publishes_status(self) -> None:
        workflow = POST_TESTING_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("needs.e2e.outputs.source_branch == 'testing'", workflow)
        self.assertIn("SHA: ${{ needs.e2e.outputs.source_sha }}", workflow)
        self.assertIn("context='e2e/post-testing'", workflow)
        self.assertIn("nvidia_image: ${{ steps.get-digest.outputs.nvidia_image }}", workflow)
        self.assertIn("image: ${{ needs.e2e.outputs.nvidia_image }}", workflow)
        self.assertIn(
            "needs: [e2e, run-e2e, run-e2e-nvidia, promote-to-testing]",
            workflow,
        )
        self.assertNotIn("run-upgrade-test", workflow)

    def test_recovery_dispatch_requires_and_validates_build_run_id(self) -> None:
        workflow = POST_TESTING_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("RUN_ID: ${{ inputs.run_id || github.event.workflow_run.id }}", workflow)
        self.assertIn("$source_branch\" != testing", workflow)
        self.assertIn("$conclusion\" != success", workflow)
        self.assertIn("$event\" != push", workflow)
        self.assertIn("SHA: ${{ needs.e2e.outputs.source_sha }}", workflow)


    def test_main_build_cannot_start_candidate_qualification(self) -> None:
        workflow = POST_TESTING_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("branches: [testing]", workflow)
        self.assertNotIn("branches: [main, testing]", workflow)
        self.assertIn("cancel-in-progress: false", workflow)


if __name__ == "__main__":
    unittest.main()
