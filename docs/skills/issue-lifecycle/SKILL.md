---
name: issue-lifecycle
version: "1.1"
last_updated: 2026-08-07
id: issue-lifecycle
one_line_purpose: Operate the repository issue lifecycle and work queue correctly.
entry_point: docs/skills/issue-lifecycle/SKILL.md
category: meta
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [issues, workflow, queue, labels]
description: >-
  Points at the canonical factory label contract and records the local
  automation and repository-specific labels layered on top of it. Use when
  picking up, updating, or closing an issue in this repository.
metadata:
  type: procedure
  source-of-truth:
    - .github/workflows/bonedigger.yml
    - .github/workflows/moderator.yml
    - .github/workflows/cherry-pick-to-stable.yml
    - docs/workflow.md
---

# Issue lifecycle

## When to Use

- Picking up, updating, or closing an issue in this repository.
- Deciding whether a label is workflow state or repository metadata.

## Do not use when

- Implementing the change itself, or debugging CI: use
  [build](../build/SKILL.md) or [ci](../ci/SKILL.md).

## Canonical contract

Do not restate it here. Read it at the source:

- Seven-label contract, ownership boundaries, and the "workflows own state,
  humans provide intent" rule:
  [`common/docs/skills/label-workflow.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
- `ujust report` intake and confirm-count priority escalation:
  [`common/docs/skills/bonedigger.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/bonedigger.md).
- Points at which to stop and ask a human:
  [`common/docs/skills/human-gates.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/human-gates.md).

Reusable lifecycle automation lives in `projectbluefin/actions` and
`projectbluefin/bonedigger`. This repository consumes it and does not own it.

## What this repository adds locally

`.github/workflows/bonedigger.yml` calls
`projectbluefin/bonedigger/.github/workflows/lifecycle.yml` (SHA-pinned, v1)
on `issues: [opened, labeled, closed]`, `issue_comment: created`,
`pull_request: opened` (branches other than `main`), and a daily cron. Its
`pull_request: opened` trigger currently dispatches no jobs — tracked in
`projectbluefin/bluefin#981`.

Beyond the seven workflow labels, `gh label list` shows labels that are *not*
lifecycle state and must never be treated as queue position:

| Label | Owner | Meaning |
|---|---|---|
| `release/ready`, `release/blocked` | release gate | Gate check result |
| `cherry-pick` | `cherry-pick-to-stable.yml` | Backport a merged PR |
| `spam`, `ai-generated` | `moderator.yml` (`github/ai-moderator`) | Moderation |
| `area/*`, `kind/*`, `priority/*` | humans | Descriptive metadata |

## Procedure

1. Read current issue state: assignment, project state, branch, linked pull
   request. Labels describe the next workflow step, not history.
2. Work only an issue routed to you by assignment, project state, or
   `3-clanker-queue`.
3. Create a worktree branch from `projectbluefin/testing`
   ([worktrees](../worktrees/SKILL.md)) and keep the change small.
4. Run the repository validation commands.
5. Open a pull request against `testing` containing `Closes #NNN`.
6. Respond to review feedback. Never self-approve or self-merge.

Agents do not use slash commands as state transitions, do not add or remove
workflow labels, and do not manufacture queue state. If blocked, describe the
exact decision or dependency in the issue and stop. Do not duplicate labels or
check-run state in comments.

Hive may route work to another repository, and Clankers is only the
authenticated relay for that assignment. Verify the target repository and issue
before acting; the relay grants no review or merge authority.

## Red Flags

- Any label outside the seven canonical workflow names being treated as state.
- A slash command being treated as a state transition.
- Queue state inferred from an issue body, comment, or stale local checkout.
- Duplicating UI state, or claiming work that is not routed to you.
- Opening a pull request against `main`.

## Verification

- [ ] `gh label list --repo projectbluefin/bluefin` shows only the seven
      workflow labels plus the metadata labels tabled above.
- [ ] `gh issue view NNN --repo projectbluefin/bluefin --json labels,assignees,state`
      confirms the issue is routed to you.
- [ ] `gh pr view --json baseRefName` reports `testing`, and the body contains
      `Closes #NNN`.
