---
name: ci
version: "1.1"
last_updated: "2026-08-07"
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
    - .pre-commit-config.yaml
  context7-sources:
    - /websites/github_en_actions
    - /podman-container-tools/buildah
---

# CI

## When to Use

- A workflow failed, did not start, or ran the wrong checks.
- A trigger, permission, path filter, or reusable workflow call changes.

## When Not to Use

- The issue is purely local validation: use [build](../build/SKILL.md).
- The change is package placement: use [packages](../packages/SKILL.md).
- The change is release procedure: use [release-artifacts](../release-artifacts/SKILL.md).

## Core Process

```bash
gh run list --repo projectbluefin/bluefin --limit 20
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
```

Read the actual workflow before describing or changing its behavior. Almost
every workflow here is a thin caller; shared logic lives in
`projectbluefin/actions` reusable workflows. Keep repo-local edits limited to
triggers, permissions, and inputs.

Start from [workflow map](references/workflow-map.md) to find the workflow that
owns the behavior, then [failure modes](references/failure-modes.md) for the
known traps in this repository's jobs.

## Branch and gate model

- Pull requests target `testing`. `pr-validation.yml`'s `check-base-branch`
  job fails any PR based on `main` unless the head is `testing` or
  `auto/promote-testing-to-main`.
- `pr-validation.yml` runs on `pull_request` → `testing` and on `merge_group`.
  The `testsuite` (E2E smoke) job only runs on `merge_group`, so a green PR is
  not proof that E2E ran.
- `build-image-testing.yml` ("Testing Images") runs on push to `main`/`testing`,
  `merge_group`, `workflow_call`, and `workflow_dispatch`. It publishes digest
  and alias tags with `publish_stream_tag: "false"`; `:testing` is moved later
  by `post-testing-e2e.yml`'s `promote-to-testing` job, which is guarded to
  `head_branch == 'main'`.
- `promote-testing-to-main.yml` delegates to
  `reusable-promote-squash.yml@v1` and uses the merge queue
  (`use_merge_queue: true`), so `gh pr merge --auto` will not work on `main`.

## Action pinning rules

`.pre-commit-config.yaml` is the enforced contract, not prose:

- `no-floating-action-tags` blocks `@main`, `@master`, `@latest`, and `@vN` for
  every action **except** `projectbluefin/actions`, `projectbluefin/bonedigger`,
  and `projectbluefin/testsuite`.
- `no-sha-pins-for-internal-actions` blocks 40-hex SHA pins for
  `projectbluefin/actions` refs — those must stay on the managed `@v1` tag.
- Everything else must be SHA-pinned with a trailing version comment.

Never call `projectbluefin/testsuite`'s `e2e.yml` from anywhere but
`.github/workflows/run-testsuite.yml`; that wrapper centralizes the ref for all
repo-local callers (`pr-validation.yml`, `post-testing-e2e.yml`, `nightly.yml`,
`e2e-dispatch.yml`).

## Lab check

Every open Bluefin PR is discovered by the lab's five-minute PR poller. The lab
runs smoke QA against `bluefin:testing` and sends bounded `repository_dispatch`
(`types: [lab-check]`) events to `.github/workflows/lab-check.yml`. That
workflow must exist on the default branch and uses a short-lived MergeRaptor
installation token to update one `testing-lab / bluefin` Check Run for the exact
PR head SHA. Do not duplicate the result in a PR comment or commit status.

## Red Flags

- Changing a caller when the behavior belongs in the reusable workflow.
- Posting a lab result as a PR comment instead of updating the MergeRaptor Check Run.
- Reading a gate's log message as proof of what it did. A step can report that a
  tag was excluded and push it anyway; confirm against the pushed artifact.
- Treating a fork PR with no checks as pending rather than unapproved.
- Adding PAT-based authentication — see
  [common secrets-policy](https://github.com/projectbluefin/common/blob/main/docs/skills/secrets-policy.md).
- Assuming a green PR means E2E ran; the smoke suite is merge-queue only.
- Documenting workflow behavior from memory instead of re-deriving it.

## Verification

```bash
actionlint .github/workflows/*.yml
just check
pre-commit run --all-files

# Current workflow inventory and triggers
grep -H '^name:' .github/workflows/*.yml
grep -rn 'uses: projectbluefin' .github/workflows/

# PR base-branch guard
grep -n 'BASE_REF' .github/workflows/pr-validation.yml

# A completed run
gh run watch RUN_ID --repo projectbluefin/bluefin --exit-status
```

## References

| Reference | Contents |
|---|---|
| [workflow map](references/workflow-map.md) | Source-derived inventory of every workflow, its trigger, and what it delegates to |
| [failure modes](references/failure-modes.md) | Triage table plus the known job-level traps (kcov coverage, `tee`, string inputs, fork approval, cache keys) |
