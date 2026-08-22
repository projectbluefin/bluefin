---
name: ci
version: "1.0"
last_updated: 2026-08-07
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
The `unit-tests` job in `pr-validation.yml` runs BATS with kcov and publishes
`bats-tap-results` plus `bats-kcov-report` artifacts for shell-test visibility.
Coverage runs route child `bash <script>` calls through
`tests/coverage/bin/bash`, because wrapping only the top-level BATS process
does not trace those child shells. The wrapper records each sandbox copy's
original source path, and `merge_kcov.py` combines those hits with kcov's
pre-parsed source inventory. A zero-line report is an instrumentation failure.
kcov is not packaged for Ubuntu 24.04, so the job builds v43 from a pinned,
SHA-256-verified source archive and caches the result. The coverage run must
redirect BATS output to a file: kcov captures child stdout through a pipe it
stops draining, so streaming the full TAP log through it deadlocks the job.
The instrumented rerun does not gate the job — `Run unit tests` owns pass/fail
— but `merge_kcov.py` fails when no source lines were executed.
Tests that `source` a library into the BATS process itself are not traced.

The `Enforce BATS coverage threshold` step's `THRESHOLD` is an evidence-based
floor, not an aspirational target: measure several recent successful
`pr-validation.yml` runs' `BATS line coverage` log lines via `gh api
repos/projectbluefin/bluefin/actions/jobs/JOB_ID/logs` before raising it, and
leave enough buffer below the observed rate to absorb normal run-to-run
variance instead of chasing the exact current percentage.

A pull request whose head branch lives on a fork reports **zero** checks until a
maintainer approves the run — identical to "checks still queued", so confirm:

```bash
gh pr view PR --repo projectbluefin/bluefin --json headRepositoryOwner,maintainerCanModify
gh api -X POST repos/projectbluefin/bluefin/actions/runs/RUN_ID/approve
```

Zero checks with no pending approval means the PR targets `main`. Retarget
with `gh pr edit PR --base testing`; rebuild branches cut from `main`.

`maintainerCanModify: true` also means fix commits can be pushed straight to the
contributor's branch.

Containerfile stages that consume source through bind mounts inherit the mounted
stage's image ID as part of their cache key. Give each consuming stage its own
narrow `scratch` context covering only the paths it reads — `ctx-build` for the
package stage, `ctx` for the overlay stages, `ctx-iso` for the ISO layer — and
pass an explicit content-hash build argument as a second guard. A shared wide
context silently couples every stage to every input directory.

Every open Bluefin PR is discovered by the lab's five-minute PR poller. The lab
runs smoke QA against `bluefin:testing` and sends bounded
`repository_dispatch` lifecycle events to `.github/workflows/lab-check.yml`.
That workflow must exist on the default branch and uses a short-lived
MergeRaptor installation token to update one `testing-lab / bluefin` Check Run
for the exact PR head SHA. Do not duplicate the result in a PR comment or commit
status.

The MergeRaptor installation on `projectbluefin` also needs **Checks: write**
for `lab-check.yml`; see [MergeRaptor checks](references/mergeraptor-checks.md).

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

`cmd | tee results.tap` reports the exit status of `tee`, not of `cmd`, so a
failing test run passes the step. Set `pipefail` or check `PIPESTATUS` whenever
a test command is piped. The authoritative BATS run in `pr-validation.yml`
enables `pipefail` before teeing `results.tap`; the separate instrumented rerun
collects coverage but does not own pass/fail.

## Hard rules

- Verify the pull request base branch before debugging missing checks.
- Preserve action pinning and workflow permissions.
- Do not add PAT-based authentication.
- Keep end-to-end suites on their configured event.
- Reference `projectbluefin/testsuite`'s reusable E2E workflow by its managed
  `@v1` tag, never a digest; testsuite advances `v1` after each successful main
  merge. It is disabled for the `github-actions` Renovate manager in
  `.github/renovate.json5`, or re-pinning freezes the gate on a stale test tree.
- Route testsuite calls through `.github/workflows/run-testsuite.yml`;
  `scripts/check-testsuite-workflow-ref.py` enforces that and `test_ref: v1`.
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
- [MergeRaptor checks](references/mergeraptor-checks.md)

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
