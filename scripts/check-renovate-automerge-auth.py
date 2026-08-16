#!/usr/bin/env python3
"""Require Renovate merges to use MergeRaptor instead of GITHUB_TOKEN."""

from pathlib import Path


WORKFLOW = Path(".github/workflows/renovate-automerge.yml")
REUSABLE_WORKFLOW = (
    "    uses: "
    "projectbluefin/actions/.github/workflows/reusable-renovate-automerge.yml@v1"
)
REQUIRED_BLOCK = """\
    secrets:
      app_id: ${{ secrets.MERGERAPTOR_APP_ID }}
      private_key: ${{ secrets.MERGERAPTOR_PRIVATE_KEY }}
"""


def _automerge_job(workflow: str) -> str:
    """Return the uncommented YAML text belonging to ``jobs.automerge``."""
    lines = workflow.splitlines(keepends=True)
    try:
        start = lines.index("  automerge:\n")
    except ValueError:
        return ""

    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line.startswith("  ") and not line.startswith("    ") and line.strip():
            end = index
            break
    return "".join(
        line for line in lines[start:end] if not line.lstrip().startswith("#")
    )


def main() -> int:
    job = _automerge_job(WORKFLOW.read_text())
    if REUSABLE_WORKFLOW not in job or REQUIRED_BLOCK not in job:
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
