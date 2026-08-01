---
name: ci
description: Debug and change repository CI workflows. Use for triggers, checks, promotion, release, or workflow failures.
metadata:
  source-of-truth:
    - .github/workflows/
    - .github/workflows/pr-validation.yml
    - .github/workflows/build-image-testing.yml
  context7-sources:
    - /websites/github_en_actions
---

# CI

## Use when

- A workflow failed, did not start, or ran the wrong checks.
- A trigger, permission, path filter, or reusable workflow call changes.

## Do not use when

- The issue is purely local validation: use [build](../build/SKILL.md).
- The change is package placement: use [packages](../packages/SKILL.md).
- The change is release procedure: use [release-artifacts](../release-artifacts/SKILL.md).

## First checks

```bash
gh run list --repo projectbluefin/bluefin --limit 20
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
```

Read the actual workflow before describing or changing its behavior. Shared
logic belongs in the reusable workflow that owns it; callers should stay thin.

Every open Bluefin PR is discovered by the lab's five-minute PR poller. The lab
runs smoke QA against `bluefin:testing` and sends bounded
`repository_dispatch` lifecycle events to `.github/workflows/lab-check.yml`.
That workflow must exist on the default branch and uses a short-lived
MergeRaptor installation token to update one `testing-lab / bluefin` Check Run
for the exact PR head SHA. Do not duplicate the result in a PR comment or commit
status.

## Hard rules

- Verify the pull request base branch before debugging missing checks.
- Preserve action pinning and workflow permissions.
- Do not add PAT-based authentication.
- Keep end-to-end suites on their configured event.
- Reference `projectbluefin/testsuite`'s reusable E2E workflow through its
  managed `@v1` tag, never an immutable digest; testsuite advances `v1` after
  each successful main-branch merge.
- Update this skill when workflow behavior changes.

## Verification

```bash
actionlint .github/workflows/*.yml
just check
pre-commit run --all-files
```

For a completed run:

```bash
gh run watch RUN_ID --repo projectbluefin/bluefin --exit-status
```

## References

- [workflow reference](references/workflow-map.md)
- [failure modes](references/failure-modes.md)

## When to Use

Use for Workflow failures, triggers, permissions, or promotion checks.

## When NOT to Use

Do not use for Pure local build or package decisions.

## Core Process

Read the affected YAML, identify the owning reusable workflow, validate locally.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Changing a caller when the behavior belongs in shared workflow logic.
- Posting a lab result as a PR comment instead of updating the MergeRaptor Check Run.
