---
name: issue-lifecycle
description: Understand and operate the repository issue lifecycle and work queue.
metadata:
  source-of-truth:
    - docs/workflow.md
    - .github/workflows/
---

# Issue lifecycle

## Procedure

1. Read the current issue labels and automation state.
2. Confirm that the issue is approved and available before claiming it.
3. Claim only work you are actively starting.
4. Return claimed work if blocked or abandoned.
5. Link implementation evidence from the pull request.

Do not duplicate labels or check-run state in comments. Treat the automation
widget and current issue state as authoritative.
