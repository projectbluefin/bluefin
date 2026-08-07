---
name: issue-lifecycle
version: "1.0"
last_updated: 2026-08-06
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
  Explains issue assignment, project state, label semantics, and the branch-
  to-pull-request path used in this repository. Use when picking up,
  updating, or closing an issue.
metadata:
  type: procedure
  source-of-truth:
    - docs/workflow.md
    - .github/workflows/
---

# Issue lifecycle

## Procedure

1. Read the current issue state: assignment, project state, branch, and linked
   pull request. Labels describe the next workflow step, not history.
2. Work only an issue routed to you by assignment, project state, or
   `3-clanker-queue`.
3. Create a scoped branch from `projectbluefin/testing` and keep the change small.
4. Run the repository validation commands.
5. Open a pull request targeting `testing` containing `Closes #NNN`
   (`gh pr create --base testing ...`; `gh pr create` defaults to the
   repository's default branch `main`, which the base-branch guard rejects).
6. Respond to review feedback; do not self-approve or self-merge.

Automation applies and repairs the seven canonical workflow labels. Agents do
not use slash commands as state transitions, do not add or remove workflow
labels, and do not manufacture queue state. If blocked, describe the exact
decision or dependency in the issue and stop.

Do not duplicate labels or check-run state in comments. Treat the automation
widget and current issue state as authoritative.

## Canonical contract

The seven-label contract and its ownership boundaries are canonical in
[`common/docs/skills/label-workflow.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
`ujust report` intake and confirm-count priority escalation are canonical in
[`common/docs/skills/bonedigger.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/bonedigger.md).
Reusable lifecycle automation lives in `projectbluefin/actions`; this repository
consumes it and does not own it.

Hive may route work to another repository, and Clankers is only the
authenticated relay for that assignment. Verify the target repository and issue
before acting; the relay grants no review or merge authority.

## When to Use

Use for Issue queue state and lifecycle operations.

## When NOT to Use

Do not use for Code implementation or CI debugging.

## Core Process

Read current automation state, perform only the next valid transition.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Any label outside the seven canonical workflow names being treated as state.
- A slash command being treated as a state transition.
- Queue state inferred from an issue body, comment, or stale local checkout.
- Duplicating UI state or claiming work that is not routed to you.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] `gh label list` shows only canonical workflow labels plus local metadata.
- [ ] The pull request links its issue with `Closes #NNN`.
- [ ] The repository default gate passes.
