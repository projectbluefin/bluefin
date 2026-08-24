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
    workflow = WORKFLOW.read_text(encoding="utf-8")
    if STEP not in workflow:
        raise AssertionError(f"{WORKFLOW.name} has no {STEP.strip()!r} step")
    body = workflow.split(STEP, 1)[1].split("        run: |\n", 1)[1]
    lines: list[str] = []
    for line in body.splitlines():
        # The step ends at the first non-blank line that leaves the run block.
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


class ReleaseWindowWiringTests(unittest.TestCase):
    """The gate is only a gate while the promote job actually consults it."""

    def test_merge_enrolment_is_driven_by_the_release_window(self) -> None:
        # `use_merge_queue` is what decides whether the promotion PR is enqueued
        # for merge. Pinned to a constant -- in either direction -- the weekday
        # check above becomes decoration, so assert the two stay wired together.
        workflow = WORKFLOW.read_text(encoding="utf-8")
        wiring = [
            line
            for line in workflow.splitlines()
            if line.strip().startswith("use_merge_queue:")
        ]
        self.assertEqual(len(wiring), 1, workflow)
        self.assertIn("needs.release_window.outputs.should_enqueue", wiring[0])

    def test_release_window_publishes_the_decision(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("should_enqueue: ${{ steps.window.outputs.should_enqueue }}", workflow)


if __name__ == "__main__":
    unittest.main()
