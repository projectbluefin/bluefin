"""Tests for the check-run reporting script in lab-check.yml.

The workflow has never run to completion in CI -- every dispatch so far dies at
the MergeRaptor token mint (bluefin#939) -- so the script below is exercised
here against a stub ``gh`` instead.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


WORKFLOW = Path(__file__).parents[1] / ".github" / "workflows" / "lab-check.yml"
STEP = "      - name: Create or update lab check\n"
REPOSITORY = "projectbluefin/bluefin"
CHECK_NAME = "testing-lab / bluefin"
SHA = "a" * 40

# Stands in for `gh api`: serves the check-runs listing from GH_STUB_CHECK_RUNS
# with the same semantics as the real endpoint -- newest first, truncated to
# per_page, filtered by check_name when asked -- and records every request.
STUB_GH = '''#!/usr/bin/env python3
import json
import os
import subprocess
import sys

arguments = sys.argv[1:]
method = "GET"
fields = {}
jq_expression = None
endpoint = None

index = 0
while index < len(arguments):
    argument = arguments[index]
    if argument == "--method":
        method = arguments[index + 1]
        index += 2
    elif argument in ("-f", "--raw-field"):
        key, _, value = arguments[index + 1].partition("=")
        fields[key] = value
        index += 2
    elif argument == "--jq":
        jq_expression = arguments[index + 1]
        index += 2
    elif argument == "--input":
        index += 2
    elif argument == "api" or argument.startswith("-"):
        index += 1
    else:
        endpoint = argument
        index += 1


def record(entry):
    with open(os.environ["GH_STUB_LOG"], "a", encoding="utf-8") as log:
        log.write(json.dumps(entry) + "\\n")


if method in ("POST", "PATCH"):
    record({"method": method, "endpoint": endpoint,
            "body": json.loads(sys.stdin.read())})
    print(json.dumps({"id": 0}))
    sys.exit(0)

if endpoint.endswith("/check-runs"):
    runs = json.loads(os.environ["GH_STUB_CHECK_RUNS"])
    name = fields.get("check_name")
    if name is not None:
        runs = [run for run in runs if run["name"] == name]
    page = runs[: int(fields.get("per_page", 30))]
    record({"method": method, "endpoint": endpoint, "check_name": name,
            "returned": len(page)})
    payload = json.dumps({"total_count": len(runs), "check_runs": page})
    if jq_expression is None:
        print(payload)
        sys.exit(0)
    result = subprocess.run(["jq", "-r", jq_expression], input=payload,
                            capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)

record({"method": method, "endpoint": endpoint})
print("{}")
'''


def report_script() -> str:
    """Return the shell body of the 'Create or update lab check' step."""
    workflow = WORKFLOW.read_text(encoding="utf-8")
    step = workflow.split(STEP, 1)[1].split("\n      - name: ", 1)[0]
    return textwrap.dedent(step.split("        run: |\n", 1)[1])


def check_run(identifier: int, name: str = CHECK_NAME,
              slug: str = "mergeraptor") -> dict:
    return {"id": identifier, "name": name, "app": {"slug": slug}}


class LabCheckReportTests(unittest.TestCase):
    def run_report(self, existing: list[dict], check: dict) -> list[dict]:
        """Run the step against `existing` check runs, newest first."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            stub = root / "gh"
            stub.write_text(STUB_GH, encoding="utf-8")
            stub.chmod(0o755)
            log = root / "requests.jsonl"
            log.touch()

            environment = dict(os.environ)
            environment.update(
                PATH=f"{root}{os.pathsep}{environment['PATH']}",
                GITHUB_REPOSITORY=REPOSITORY,
                SHA=SHA,
                CHECK_JSON=json.dumps(check),
                GH_TOKEN="stub-token",
                GH_STUB_LOG=str(log),
                GH_STUB_CHECK_RUNS=json.dumps(existing),
            )

            result = subprocess.run(
                ["bash", "-c", report_script()],
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return [
                json.loads(line)
                for line in log.read_text(encoding="utf-8").splitlines()
            ]

    def test_updates_existing_check_buried_past_the_first_page(self) -> None:
        # A commit that has collected more check runs than one page holds: the
        # lab check is the oldest, so an unfiltered listing would never see it.
        existing = [check_run(9000 + index, name="e2e") for index in range(150)]
        existing.append(check_run(1234))

        requests = self.run_report(
            existing,
            {"state": "completed", "conclusion": "success",
             "summary": "All lab suites passed."},
        )

        writes = [r for r in requests if r.get("method") in ("POST", "PATCH")]
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0]["method"], "PATCH")
        self.assertTrue(writes[0]["endpoint"].endswith("/check-runs/1234"))
        # head_sha is immutable on an existing run; sending it is rejected.
        self.assertNotIn("head_sha", writes[0]["body"])
        self.assertEqual(writes[0]["body"]["conclusion"], "success")

        listing = next(r for r in requests if r["endpoint"].endswith("check-runs"))
        self.assertEqual(listing["check_name"], CHECK_NAME)

    def test_creates_check_when_the_commit_has_none(self) -> None:
        requests = self.run_report(
            [check_run(9001, name="e2e")],
            {"state": "in_progress", "title": "Lab validation",
             "summary": "Lab run started.",
             "details_url": "https://lab.example/run/7"},
        )

        writes = [r for r in requests if r.get("method") in ("POST", "PATCH")]
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0]["method"], "POST")
        body = writes[0]["body"]
        self.assertEqual(body["name"], CHECK_NAME)
        self.assertEqual(body["head_sha"], SHA)
        self.assertEqual(body["status"], "in_progress")
        self.assertNotIn("conclusion", body)
        self.assertEqual(body["details_url"], "https://lab.example/run/7")

    def test_ignores_a_same_named_check_from_another_app(self) -> None:
        requests = self.run_report(
            [check_run(4321, slug="some-other-app")],
            {"state": "completed", "conclusion": "failure",
             "summary": "Lab run failed."},
        )

        writes = [r for r in requests if r.get("method") in ("POST", "PATCH")]
        self.assertEqual(writes[0]["method"], "POST")


if __name__ == "__main__":
    unittest.main()


class LabCheckConcurrencyTests(unittest.TestCase):
    """The workflow must serialise lifecycle events that share a head SHA.

    Reporting is a read-then-write -- look up the existing check run, then POST
    or PATCH -- so two runs for one SHA that overlap both find nothing and both
    POST, duplicating `testing-lab / <product>` and stranding all but one in a
    non-terminal state (bluefin#939).
    """

    def concurrency_block(self) -> str:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        # A leading newline with no indent pins this to the workflow level; a
        # job-level `concurrency:` would not serialise across runs.
        marker = "\nconcurrency:\n"
        self.assertIn(marker, workflow, "lab-check.yml declares no concurrency group")
        self.assertLess(
            workflow.index(marker),
            workflow.index("\njobs:"),
            "concurrency must be declared before jobs, at the workflow level",
        )
        return workflow.split(marker, 1)[1].split("\njobs:", 1)[0]

    def test_group_is_keyed_on_the_dispatched_head_sha(self) -> None:
        block = self.concurrency_block()
        group = [line for line in block.splitlines() if line.strip().startswith("group:")]
        self.assertEqual(len(group), 1, block)
        # Keying on the payload SHA is what makes this safe: it serialises the
        # events for one commit while leaving different PRs to report in
        # parallel, which the lab's five-minute poller relies on.
        self.assertIn("github.event.client_payload.sha", group[0])

    def test_in_flight_runs_are_not_cancelled(self) -> None:
        # Cancelling can kill the run applying the terminal `completed` event
        # and leave the check stuck in_progress for good.
        self.assertIn("cancel-in-progress: false", self.concurrency_block())
