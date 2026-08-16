#!/usr/bin/env python3
"""Require Renovate merges to use MergeRaptor instead of GITHUB_TOKEN."""

from pathlib import Path


WORKFLOW = Path(".github/workflows/renovate-automerge.yml")
REQUIRED_BLOCK = """\
    secrets:
      app_id: ${{ secrets.MERGERAPTOR_APP_ID }}
      private_key: ${{ secrets.MERGERAPTOR_PRIVATE_KEY }}
"""


def main() -> int:
    workflow = WORKFLOW.read_text()
    if REQUIRED_BLOCK not in workflow:
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
