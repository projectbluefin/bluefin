#!/usr/bin/env python3
"""Require Renovate merges to use MergeRaptor instead of GITHUB_TOKEN."""

from pathlib import Path

import yaml


WORKFLOW = Path(".github/workflows/renovate-automerge.yml")

REUSABLE_WORKFLOW = (
    "projectbluefin/actions/.github/workflows/reusable-renovate-automerge.yml@v1"
)
REQUIRED_SECRETS = {
    "app_id": "${{ secrets.MERGERAPTOR_APP_ID }}",
    "private_key": "${{ secrets.MERGERAPTOR_PRIVATE_KEY }}",
}


def main() -> int:
    try:
        workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        workflow = None

    job = (
        workflow.get("jobs", {}).get("automerge", {})
        if isinstance(workflow, dict)
        else {}
    )
    if (
        not isinstance(job, dict)
        or job.get("uses") != REUSABLE_WORKFLOW
        or job.get("secrets") != REQUIRED_SECRETS
    ):
        print("Renovate auto-merge authentication contract failed:")
        print(
            "The automerge job must pass the adjacent app_id and private_key "
            "MergeRaptor secrets so the resulting testing-branch push can "
            "trigger image builds."
        )
        return 1

    print("Renovate auto-merge authentication contract passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
