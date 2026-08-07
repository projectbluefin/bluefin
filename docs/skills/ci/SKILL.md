---
name: ci
version: "1.0"
last_updated: 2026-08-06
id: ci
one_line_purpose: Debug and change repository GitHub Actions workflows.
entry_point: docs/skills/ci/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [ci, workflows, github-actions, triggers, debugging]
description: >-
  Explains workflow triggers, path filters, reusable workflow calls, and how
  to read failing runs in this repository. Use when a workflow failed, did
  not start, or ran the wrong checks.
metadata:
  type: runbook
  source-of-truth:
    - .github/workflows/
    - .github/workflows/pr-validation.yml
    - .github/workflows/build-image-testing.yml
  context7-sources:
    - /websites/github_en_actions
    - /podman-container-tools/buildah
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

A pull request whose head branch lives on a fork reports **zero** checks until a
maintainer approves the run. That looks identical to "checks still queued", so
confirm the state before waiting on it:

```bash
gh pr view PR --repo projectbluefin/bluefin --json headRepositoryOwner,maintainerCanModify
gh api -X POST repos/projectbluefin/bluefin/actions/runs/RUN_ID/approve
```

`maintainerCanModify: true` also means fix commits can be pushed straight to the
contributor's branch.

Containerfile stages that consume source through bind mounts inherit the mounted
stage's image ID as part of their cache key. Give the package stage its own
narrow `scratch` context so unrelated edits do not invalidate it, and pass an
explicit content-hash build argument as a second guard.

Every open Bluefin PR is discovered by the lab's five-minute PR poller. The lab
runs smoke QA against `bluefin:testing` and sends bounded
`repository_dispatch` lifecycle events to `.github/workflows/lab-check.yml`.
That workflow must exist on the default branch and uses a short-lived
MergeRaptor installation token to update one `testing-lab / bluefin` Check Run
for the exact PR head SHA. Do not duplicate the result in a PR comment or commit
status.

## Workflow input and job constraints

A `type: string` input is truthy in an `if:` even when its value is `"false"`.
Gating on the bare input therefore fails **open**. Compare explicitly and treat
any unexpected value as the safe state:

```yaml
if: inputs.publish_stream_tag == 'true'
```

A job that calls a reusable workflow accepts only `name`, `uses`, `with`,
`secrets`, `needs`, `if`, and `permissions`. `continue-on-error` and
`runs-on` are rejected, so a reusable-workflow call cannot be made advisory —
it either gates or it is absent. `actionlint` catches this.

A job listed in `needs:` without `always()` makes its dependents `skipped` when
it fails. Confirm whether a promotion job is *failing* or *never running*; the
two look the same in the UI and have different fixes.

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
- Reading a gate's log message as proof of what it did. A step can report that a
  tag was excluded and push it anyway; confirm against the pushed artifact.
- Treating a fork PR with no checks as pending rather than unapproved.
