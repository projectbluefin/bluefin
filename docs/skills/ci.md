# CI/CD Reference

## When to use
- A GitHub Actions workflow failed
- A PR has no checks or the wrong checks
- Promotion or release behavior looks wrong
- Renovate automerge is stuck

## When NOT to use
- Pure local validation issues → [build.md](build.md)
- Package placement decisions → [packages.md](packages.md)
- ISO pipeline work → [iso.md](iso.md)

## First triage
```bash
gh run list --repo projectbluefin/bluefin --limit 20
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
```

## Workflow map (all 24 workflows)

| Workflow | Trigger | Purpose |
|---|---|---|
| `bonedigger.yml` | Issue events, daily | Issue lifecycle automation |
| `build-image-testing.yml` | Push to `main`+`testing` (paths-filtered), `merge_group`, dispatch, `workflow_call` | Testing image builds via `reusable-build.yml@v1`. Sets `publish_stream_tag: false` — does **not** apply `:testing` tag directly |
| `cache-maintenance.yml` | Monday 06:00 UTC, dispatch | Audits and prunes GHA caches (warns ≥80% of 10 GB limit; prunes deleted-branch or 14d-stale caches) |
| `cherry-pick-to-stable.yml` | `cherry-pick` label applied to a PR | Backports the PR to the `stable` branch via GitHub App token |
| `consumer-validate-generate-release-notes.yml` | PRs to `testing` touching this file or `docs/skills/ci.md`, dispatch | Contract-tests the shared `generate-release-notes@v1` action from `projectbluefin/actions` |
| `copr-health-monitor.yml` | Daily 07:00 UTC | COPR staleness check → opens issue on failure |
| `e2e-dispatch.yml` | `/e2e` comment (write+ only) | Manual E2E trigger on a PR |
| `execute-release.yml` | Push to `main`, dispatch | Detects promotion by commit message pattern `^chore: promote testing to main`; delegates to `reusable-execute-release.yml@v1` → copies `:testing`→`:stable` |
| `moderator.yml` | Issues/comments | AI spam detection |
| `nightly.yml` | 02:00 UTC daily, dispatch | Runs `smoke,common,vanilla-gnome` suites against `:testing`. Diagnostic: smoke=fail+vanilla-gnome=pass → Bluefin-specific regression; both fail → upstream GNOME issue |
| `pkg-cadence.yml` | After `Execute Release` completes, dispatch | Measures per-package update frequency after each release via `reusable-pkg-cadence.yml@v1` |
| `post-testing-e2e.yml` | `workflow_run: ["Testing Images"]` (completed, branches: main+testing) | Downloads build digest; runs `smoke,common` E2E; `promote-to-testing` job copies digests to `:testing` tag — **only when `head_branch == 'main'`** |
| `pr-release-gate.yml` | PRs to `main` (job runs only for `auto/promote-testing-to-main` head) | **DELETED** — gate logic now runs inside `reusable-promote-squash.yml`. This file no longer exists. |
| `pr-validation.yml` | PRs to `testing`, `merge_group` | `check-base-branch` (fails PRs targeting `main` unless from `auto/promote-testing-to-main`) → `validate` → `unit-tests` → `testsuite` (merge_group only) |
| `promote-testing-to-main.yml` | Daily 04:00 UTC, dispatch | Opens/updates `auto/promote-testing-to-main` squash PR via `reusable-promote-squash.yml@v1`; uses merge queue (`enqueuePullRequest` GraphQL) — `gh pr merge --auto` is blocked |
| `release-reminder.yml` | Daily 12:00 UTC, dispatch | Posts overdue-release reminders via `reusable-release-reminder.yml@v1` (warn at 7d, escalate at 14d) |
| `renovate-automerge.yml` | `workflow_run: ["PR Validation — testsuite"]` (completed) | Auto-merges qualifying Renovate PRs via `reusable-renovate-automerge.yml@v1` |
| `run-testsuite.yml` | Called by all E2E workflows | **Canonical testsuite wrapper** — always use this, never call the testsuite directly |
| `scorecard.yml` | Push to `main`, weekly | OSSF Scorecard security assessment → Security tab |
| `skill-drift.yml` | PRs to `testing` | Warns when `.github/workflows/**`, `build_files/**`, `Justfile`, or `recipes/**` change without a matching `docs/skills/**` or `docs/*.md` update |
| `sync-main-to-testing.yml` | Push to `main` | Merges `main`→`testing` after squash promotion; also deletes the `auto/promote-testing-to-main` branch |
| `track-common.yml` | `repository_dispatch: common-updated`, dispatch | Updates `image-versions.yml` with latest `ghcr.io/projectbluefin/common:latest` digest via Mergeraptor app |
| `validate-renovate.yml` | PRs touching Renovate configs, dispatch | Validates Renovate configuration |
| `vulnerability-scan.yml` | Testing build completion + weekly | Grype CVE scan → SARIF upload to Security tab |

## Fast checks by symptom

### PR has no CI
- Confirm the PR targets `testing` (not `main`)
- Confirm changed files are not excluded by workflow path filters
- Re-open or retarget if needed

### `just check` failed in CI
```bash
just check
```

### pre-commit failed in CI
```bash
pre-commit run --all-files
```

### shellcheck failed in CI
```bash
shellcheck build_files/**/*.sh
```

## Promotion pipeline mental model

```
PR merges to testing
  └─ build-image-testing.yml builds the image (publish_stream_tag: false — no :testing tag yet)
       └─ post-testing-e2e.yml fires (workflow_run on "Testing Images", both branches)
            └─ smoke + common E2E suites run
                 └─ promote-testing-to-main.yml fires (daily 04:00 UTC)
                      └─ reusable-promote-squash.yml opens/updates auto/promote-testing-to-main PR
                           └─ cosign verify + smoke,common E2E gate (runs inside reusable-promote-squash.yml)
                                └─ merge queue: pr-validation.yml runs validate on merge-group → squash-merge to main
                                     └─ execute-release.yml: :testing → :stable
                                     └─ sync-main-to-testing.yml: merges main→testing; deletes promotion branch
                                          └─ build-image-testing.yml fires on main push
                                               └─ post-testing-e2e.yml (head_branch == 'main'): tags :testing
```

**Key facts:**
- `:testing` tag is applied by `post-testing-e2e.yml → promote-to-testing` job, and **only** when `head_branch == 'main'` (after a build on `main`, not `testing`)
- `execute-release.yml` triggers by commit message pattern `^chore: promote testing to main`, not a schedule
- There is no `weekly-testing-promotion.yml` — that workflow does not exist

### Testing→main squash history gap
`promote-testing-to-main.yml` squash-merges `testing → main`. Feature PRs were already squash-merged into `testing`, so the squash on `main` creates a new SHA — graphs diverge. `sync-main-to-testing.yml` reconciles by merging `main` back into `testing` after each promotion. Tracked in [#368](https://github.com/projectbluefin/bluefin/issues/368).

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| PR has no status checks | PR targets `main` not `testing` | `gh pr edit <n> --base testing` |
| `just check` or `pre-commit` fails in CI but not locally | Hooks not installed locally | `pre-commit install && pre-commit run --all-files` |
| Unit tests pass locally, fail in CI | Running single file locally vs. `bats tests/unit/` in CI | Run `bats tests/unit/` locally |
| `:testing` tag not updated after testing branch build | `promote-to-testing` only runs for `main` branch builds | Normal; tag updates after promotion cycle completes |
| Promotion PR stuck, no `release/ready` label | `reusable-promote-squash.yml` waiting for post-testing-e2e to pass | Trigger `gh run rerun` on failed post-testing-e2e run |
| `promote-testing-to-main.yml` enqueue fails | Merge queue `validate` check missing on squash HEAD; GITHUB_TOKEN pushes do not trigger pr-validation.yml | `reusable-promote-squash.yml@v1` posts `validate=success` on the squash HEAD before `enqueuePullRequest`. Caller workflow `promote-testing-to-main.yml` mirrors `validate=success` to the merge-group HEAD SHA (`mergeQueueEntry.headCommit.oid`) so HEADGREEN can complete. Ruleset 17070404 must not set `integration_id` on the `validate` check (so Status API posts satisfy it). |
| `sync-main-to-testing.yml` fails | Merge conflict between `main` and `testing` | Manual merge + force-push to `testing` per `workflow.md` |
| `track-common.yml` not firing | `repository_dispatch: common-updated` not sent by `common` | Manual: `gh workflow run track-common.yml --repo projectbluefin/bluefin` |
| Renovate PR not automerging | `PR Validation — testsuite` did not complete successfully | Check `pr-validation.yml`; ensure `validate` job passed |
| `skill-drift.yml` warning | Workflow/build change without matching `docs/skills/` update | Update the relevant skill file in the same PR |
| `execute-release.yml` `release-notes` job fails (OOM, exit 137) | `generate_sbom_inline: true` re-pulls the full image from the registry at release time, OOM-killing the runner | **Do not use `generate_sbom_inline: true`.** Keep artifact mode in `execute-release.yml`. |
| `execute-release.yml` is green but release package table is empty/minimal | `actions/download-artifact` could not find `sbom-*` for the selected run and reusable-release used placeholder SPDX fallback | Trigger a fresh build run that uploads the expected SBOM artifact, then rerun `execute-release.yml`. |
| Merge queue dequeues PR immediately after enqueue | GITHUB_TOKEN-created PRs generate `action_required` check suites for any `pull_request`-triggered workflow — HEADGREEN treats these as non-green | Removed `pull_request: branches: main` from `build-image-testing.yml`, `pr-validation.yml`, and deleted `pr-release-gate.yml` (gate runs inside `reusable-promote-squash.yml`). After the fix, only `validate=success` exists on the squash SHA, HEADGREEN fires merge_group. If recurs: check for new workflows with `pull_request: branches: main` trigger. |
| Merge queue stays AWAITING_CHECKS indefinitely | `validate` status exists on PR/squash SHA but not on merge-group SHA | `promote-testing-to-main.yml` now mirrors `validate=success` to `mergeQueueEntry.headCommit.oid` after enqueue. If still blocked, inspect the mirror step and post manually: `gh api repos/projectbluefin/bluefin/statuses/<merge-group-sha> --method POST -f state=success -f context=validate`. |
| `promote-testing-to-main.yml` fails: `protected branch hook declined` on `auto/promote-testing-to-main` | PR is in the merge queue; GitHub locks the squash branch against force-pushes while it's being processed | Expected transient failure — do not retry until the merge queue finishes or times out (15 min). After dequeue, re-run: `gh workflow run promote-testing-to-main.yml --repo projectbluefin/bluefin --ref testing`. |
| `promote-testing-to-main.yml` fails: HTTP 403 on Statuses API | `promote` job missing `statuses: write` permission | Fixed in `reusable-promote-squash.yml@v1` (PR#292). If recurs: check job-level permissions block. |
| Checkout fails with `No url found for submodule path '.workflow-scripts' in .gitmodules` | A gitlink was committed without a matching `.gitmodules` entry | Remove the stray gitlink (`git rm -f .workflow-scripts`), then verify every remaining mode `160000` path is declared in `.gitmodules` |

## Non-obvious patterns

- **`:testing` tag assignment:** `build-image-testing.yml` sets `publish_stream_tag: false`. The `:testing` tag is only applied by `post-testing-e2e.yml → promote-to-testing`, and only when `head_branch == 'main'`.
- **Promotion trigger source:** `execute-release.yml` must match the squash-merged promotion commit title on `main` (`chore: promote testing to main`), not the PR title. `reusable-promote-squash.yml` creates that branch commit title before the PR is opened.
- **Merge queue, not auto-merge:** `promote-testing-to-main.yml` uses `use_merge_queue: true` → GraphQL `enqueuePullRequest`. `gh pr merge --auto --squash` is blocked by ruleset 17070404.
- **`promote-testing-to-main.yml` has 3 triggers:** push to `testing`, daily 04:00 UTC, and `workflow_dispatch`.
- **`validate` check on squash branch AND merge group:** `reusable-promote-squash.yml@v1` posts `validate=success` on the squash branch HEAD before enqueue. Then the caller mirrors `validate=success` to `mergeQueueEntry.headCommit.oid` (merge-group SHA) so HEADGREEN does not time out waiting for checks.
- **`pr-validation.yml` only fires on PRs to `testing`** and on `merge_group`. The `check-base-branch` job blocks human PRs accidentally targeting `main`. The `auto/promote-testing-to-main` PR is exempted from that check. Do not add `main` back to the `pull_request: branches` list — this would create `action_required` check suites that block the HEADGREEN merge queue.
- **Gitlinks must be declared:** Bluefin has legitimate submodules under `system_files/shared/...`, so the CI guard in `pr-validation.yml` does **not** ban mode `160000` entries outright. It fails only when a gitlink path is missing from `.gitmodules` (for example a stray `.workflow-scripts` entry).
- **Guard inspects the PR head tree:** the undeclared-gitlink check reads `github.event.pull_request.head.sha` on PRs instead of the synthetic merge ref, so a testing→main promotion PR can pass once the `testing` head no longer carries the stray gitlink even if `main` still does.
- **E2E (`testsuite` job) only runs on `merge_group`** — per-push PR CI is fast: `validate` + `unit-tests` only (~2 min).
- **Unit tests run the whole directory:** `bats --formatter tap tests/unit/` — not a specific file.
- **`consumer-validate-generate-release-notes.yml` intentionally uses `@v1`** (not SHA-pinned) so action fixes propagate without a Renovate bump. Explicit exception to the SHA-pinning rule.
- **Two GitHub App identities:** `MERGERAPTOR` (used by `track-common.yml`) and `BLUEFINBOT` (used historically; `sync-main-to-testing.yml` now uses `github.token` directly).
- **Artifact names include architecture suffix:** `image-digest-testing-bluefin-main-x86_64` (not `image-digest-testing-bluefin-main`).
- **`production` environment branch policy:** use `custom_branch_policies: true` with `main` explicitly added. `protected_branches: true` does NOT recognize GitHub rulesets.
- **SBOM is generated at build time, not release time:** `reusable-build` runs Syft via `just gen-sbom` while the image layers are already on disk and uploads `sbom-<image>` as a GHA artifact. `Justfile` must use `--catalogers rpm` and output `spdx-json` to avoid runner OOMs and ensure compatibility with the release action. `execute-release.yml` must reference it via `sbom_artifact` + `build_workflow` + `build_branch`. Never use `generate_sbom_inline: true` — that re-pulls the full image from the registry onto the release runner (8 GB → OOM). Dakota has always done this correctly; bluefin and bluefin-lts were fixed in PR #730 / bluefin-lts #385.
- **Missing artifact is a known path:** `actions/download-artifact@v8` errors when a named artifact is absent. `reusable-release.yml@v1` now treats artifact download as non-blocking and writes a minimal SPDX fallback so release publication does not fail; rerun after a build that produced real SBOM artifacts when package inventory quality matters.


## Shared actions architecture (projectbluefin/actions)

All workflow files are thin callers. Shared logic lives in `projectbluefin/actions`.

| Reusable | Caller in this repo |
|---|---|
| `reusable-build.yml` | `build-image-testing.yml` |
| `reusable-promote-squash.yml` | `promote-testing-to-main.yml` |
| `reusable-execute-release.yml` | `execute-release.yml` |
| `reusable-sync-branches.yml` | `sync-main-to-testing.yml` |
| `reusable-vulnerability-scan.yml` | `vulnerability-scan.yml` |
| `reusable-renovate-automerge.yml` | `renovate-automerge.yml` |
| `reusable-release-reminder.yml` | `release-reminder.yml` |
| `reusable-pkg-cadence.yml` | `pkg-cadence.yml` |
| `skill-drift-check.yml` | `skill-drift.yml` |
| `generate-release-notes` (action) | `consumer-validate-generate-release-notes.yml` |

### Caller pinning rule
- Use `@v1` managed tag for all `projectbluefin/actions` references.
- `no-sha-pins-for-internal-actions` pre-commit hook **blocks SHA pins** for `projectbluefin/` actions.
- `no-floating-action-tags` exempts `projectbluefin/` refs so `@v1` is allowed.
- Renovate does NOT update `projectbluefin/` action refs.

### CI fix workflow for agents

Before fixing something here, check whether the logic belongs in `projectbluefin/actions`:

| Belongs in `projectbluefin/actions` | Stays in this repo |
|---|---|
| Shared step sequences used by ≥2 workflows or repos | Repo-specific triggers, schedules, concurrency |
| Third-party action SHA pins | Caller permissions scoping |
| Logic shared across bluefin, bluefin-lts, dakota | Repo-specific Justfile recipes |

Correct sequence:
1. Open PR in `projectbluefin/actions` on a feature branch
2. Open draft PR here pinned to the feature branch SHA
3. CI must pass before the actions PR merges
4. After actions PR merges, `v1` is fast-forwarded — no update needed here

## Hard rules for agents
- PRs always target `testing`. Never `main`.
- Never add shared CI logic here. New reusable actions go in `projectbluefin/actions` only.
- Never inline a third-party action already wrapped in `projectbluefin/actions`.
- All workflow files are thin callers — no inline business logic.
- Workflow behavior changes must update `docs/skills/ci.md` in the same PR. `skill-drift.yml` warns if you forget.
- Read the actual workflow files before writing about them. Source wins over memory.
- **PATs are forbidden.** Never add `RENOVATE_TOKEN` or any PAT secret.
- Always verify build completion: `gh run watch <id> --exit-status`
