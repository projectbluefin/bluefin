# Workflow map

Reference for [`../SKILL.md`](../SKILL.md). `.github/workflows/` is
authoritative; this inventory is source-derived and must be updated whenever a
workflow is added, removed, renamed, or retargeted. Re-derive it with the
commands in [Verification](#verification).

## Pull request and merge gates

| File | Workflow name | Trigger | Delegates to |
|---|---|---|---|
| `pr-validation.yml` | PR Validation — testsuite | `pull_request` → `testing`, `merge_group` | `actions/bootc-build/validate-pr@v1`; local `unit-tests`; `run-testsuite.yml` (merge_group only) |
| `build-image-testing.yml` | Testing Images | push to `main`/`testing`, `merge_group`, `workflow_call`, `workflow_dispatch` | `actions/.github/workflows/reusable-build.yml@v1` |
| `promote-testing-to-main.yml` | Promote testing to main | push to `testing`, daily 04:00 UTC, dispatch | `actions/.github/workflows/reusable-promote-squash.yml@v1` |
| `sync-main-to-testing.yml` | Sync main → testing | push to `main` | `actions/.github/workflows/reusable-sync-branches.yml@v1` |
| `cherry-pick-to-stable.yml` | Backport Merged Pull Requests | `pull_request_target` closed | repo-local backport steps |

## E2E

| File | Workflow name | Trigger | Notes |
|---|---|---|---|
| `run-testsuite.yml` | Run Testsuite | `workflow_call` | Canonical wrapper for `projectbluefin/testsuite`'s `e2e.yml`. Never call testsuite directly from another workflow. |
| `post-testing-e2e.yml` | Post-Testing E2E | `workflow_run` on "Testing Images" (`main`, `testing`) | Runs `smoke,common`, then `promote-to-testing` moves `:testing` by digest — guarded to `head_branch == 'main'`. `run-upgrade-test` is commented out (TODO #400). |
| `nightly.yml` | Nightly E2E | daily 02:00 UTC, dispatch | `smoke,common,vanilla-gnome` against `:testing` |
| `e2e-dispatch.yml` | E2E Dispatch | `issue_comment` | Comment-driven dispatch into `build-image-testing.yml` with `pr_number`, then `run-testsuite.yml` against the PR image |
| `lab-check.yml` | Lab check | `repository_dispatch` `[lab-check]` | Updates the `testing-lab / bluefin` Check Run via a MergeRaptor app token |

## Release

| File | Workflow name | Trigger | Delegates to |
|---|---|---|---|
| `execute-release.yml` | Execute Release | push to `main`, dispatch | `reusable-execute-release.yml@v1`, `reusable-release.yml@v1` |
| `release-reminder.yml` | Release Reminder | daily 12:00 UTC, dispatch | `reusable-release-reminder.yml@v1` |
| `consumer-validate-generate-release-notes.yml` | Consumer validate shared generate-release-notes action | PR → `testing` touching itself or `docs/skills/ci/**` | `actions/bootc-build/generate-release-notes@v1` |

## Security and supply chain

| File | Workflow name | Trigger | Delegates to |
|---|---|---|---|
| `vulnerability-scan.yml` | Vulnerability Scan | `workflow_run` on "Testing Images" (`main`), weekly Mon 08:00 UTC, dispatch | `reusable-vulnerability-scan.yml@v1` for `bluefin` and `bluefin-nvidia` |
| `scorecard.yml` | Scorecard supply-chain security | `branch_protection_rule`, weekly Tue, push to `main` | OpenSSF Scorecard |
| `copr-health-monitor.yml` | COPR Health Monitor | daily 07:00 UTC, dispatch | Repo-local COPR API health probe; opens issues |

## Dependencies and maintenance

| File | Workflow name | Trigger | Delegates to |
|---|---|---|---|
| `renovate-automerge.yml` | Renovate Auto-merge | `workflow_run` on "PR Validation — testsuite" | `reusable-renovate-automerge.yml@v1` |
| `validate-renovate.yml` | Validate Renovate Config | PR (not `main`) / push to `main` on `.github/renovate.json5` paths | `reusable-validate-renovate.yml@v1` |
| `track-common.yml` | Track Common Image | `repository_dispatch` `[common-updated]`, dispatch | Updates `image-versions.yml` |
| `pkg-cadence.yml` | Update package cadence intervals | `workflow_run` on "Execute Release", dispatch | `reusable-pkg-cadence.yml@v1` |
| `cache-maintenance.yml` | Cache Maintenance | weekly Mon 06:00 UTC, dispatch | Repo-local Actions cache pruning |

## Community automation

| File | Workflow name | Trigger | Delegates to |
|---|---|---|---|
| `bonedigger.yml` | issue and PR lifecycle | issues, issue comments, PR opened (not `main`), daily 09:00 UTC | `projectbluefin/bonedigger/.github/workflows/lifecycle.yml` (SHA-pinned `# v1`) |
| `moderator.yml` | AI Moderator | issues opened, issue comments, PR review comments | Repo-local moderation |

## Verification

```bash
# Full inventory with names
grep -H '^name:' .github/workflows/*.yml

# Triggers for one workflow
sed -n '/^on:/,/^[a-z]/p' .github/workflows/<file>.yml

# Every external / reusable workflow reference and its pin
grep -rn 'uses: projectbluefin' .github/workflows/
```
