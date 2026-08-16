#!/usr/bin/env python3
"""Require Renovate merges to use MergeRaptor instead of GITHUB_TOKEN."""

from pathlib import Path


WORKFLOW = Path(".github/workflows/renovate-automerge.yml")
REQUIRED_LINES = (
    "    secrets:\n",
    "      app_id: ${{ secrets.MERGERAPTOR_APP_ID }}\n",
    "      private_key: ${{ secrets.MERGERAPTOR_PRIVATE_KEY }}\n",
)


def main() -> int:
    workflow = WORKFLOW.read_text()
    missing = [line.strip() for line in REQUIRED_LINES if line not in workflow]
    if missing:
        print("Renovate auto-merge authentication contract failed:")
        for line in missing:
            print(f" - missing: {line}")
        print(
            "Use the MergeRaptor App token so the resulting testing-branch push "
            "can trigger image builds."
        )
        return 1

    print("Renovate auto-merge authentication contract passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
