# CI/CD Troubleshooting

## When to use

- A GitHub Actions workflow failed
- A PR has no checks or the wrong checks
- Testing/stable/latest promotion behavior looks wrong
- Release generation or automerge is stuck

## When NOT to use

- Pure local validation issues → [build.md](build.md)
- Package placement decisions → [packages.md](packages.md)
- ISO pipeline work in the separate repo → [iso.md](iso.md)

## First triage

List recent runs:
```bash
gh run list --repo projectbluefin/bluefin --limit 20
```

Inspect a failed run:
```bash
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
```

Retry only failed jobs:
```bash
gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
```

## Workflow map (high-signal workflows)

| Workflow | Trigger | Purpose |
|---|---|---|
| `promote-testing-to-main.yml` | Push to `testing`, daily 23:00 UTC, manual dispatch | Upserts the long-lived `testing` → `main` promotion PR and enables squash auto-merge |
| `sync-main-to-testing.yml` | Push to `main` | Merges `main` → `testing` after each squash-merge promotion; prevents next promotion PR opening `BEHIND` |
| `pr-smoke.yml` | PRs touching build files | Full image build + smoke test |
| `build-image-testing.yml` | Push to `main`, dispatch | Testing image builds via centralized `projectbluefin/actions` workflow |
| `post-testing-e2e.yml` | Testing build on `main` | Smoke+common continuous e2e gate |
| `weekly-testing-promotion.yml` | Tuesday 06:00 UTC | Full e2e → retag to :stable + generate release |
| ~~`reusable-build.yml`~~ (deleted) | Replaced by `projectbluefin/actions/.github/workflows/reusable-build.yml` | **All build callers now use the centralized workflow — no local copy** |
| `run-testsuite.yml` | Called by all e2e workflows | **Canonical testsuite wrapper — always use this, never e2e.yml directly** |
| `nightly.yml` | 02:00 UTC daily | smoke+common+vanilla-gnome against :testing |
| `vulnerability-scan.yml` | Testing build + weekly | Grype → SARIF to Security tab |
| `renovate-automerge.yml` | PR Validation success | Auto-merge all Renovate/mergeraptor PRs via `gh pr merge --auto --squash` (no high-risk/smoke distinction) |
| `e2e-dispatch.yml` | `/e2e` comment (write+ only) | Manual e2e on PR |
| `generate-release.yml` | Stable build, dispatch | GitHub Release + changelog |
| `copr-health-monitor.yml` | Daily 07:00 UTC | COPR staleness check |
| `check-cosign-key-rotation.yml` | Monday 06:00 UTC | Key rotation detection → P1 issue |
| `cache-maintenance.yml` | Monday 06:00 UTC | GHA cache pruning |
| `clean.yml` | Sunday 00:15 UTC | GHCR image cleanup (>90d) |
| `scorecard.yml` | Push to main, weekly | OSSF Scorecard |
| `cherry-pick-to-stable.yml` | `cherry-pick` label on PR | Backport via GitHub App token |
| `bonedigger.yml` | Issue events, daily | Issue lifecycle |
| `moderator.yml` | Issues/comments | AI spam detection |
| `skill-drift.yml` | PRs to `testing` (on `testing` branch) / PRs to `main` (on `main` branch) | Guardrail: workflow/build changes must update matching docs/skills. SHA-pinned (`@6274199cfb...`). Includes `.github/actions/**` in code-paths. |

## Fast checks by symptom

### PR has no CI
- Confirm the PR targets `testing`
- Confirm the changed files are not excluded by workflow path filters
- Re-open or retarget the PR if needed

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

### Bluefin (this repo)

1. Push to `testing` → `build-image-testing.yml` publishes `:testing` images (gated behind post-build e2e)
2. `post-testing-e2e.yml` smoke-tests that exact digest
3. `weekly-testing-promotion.yml` (Tuesday 06:00 UTC) locks the `:testing` digest, verifies e2e passed, cosign-verifies, skopeo-copies → `:stable`, generates GitHub release
4. 7-day floor enforced; `workflow_dispatch` bypasses it
5. A separate `promote-testing-to-main.yml` keeps the `testing → main` git branch in sync via a squash-merge PR (see **testing→main squash history gap** below)

### Dakota

Same digest-promotion model. `weekly-testing-promotion.yml` resolves `:testing` digest, runs e2e, cosign-verifies, skopeo-copies → `:stable`. No git branch PR.

### Bluefin LTS

**Current state:** `scheduled-lts-release.yml` dispatches fresh weekly builds from the `lts` branch (rebuilds from source — violates build-once principle).
**Target state:** digest promotion matching bluefin/dakota — tracked in [bluefin-lts#77](https://github.com/projectbluefin/bluefin-lts/issues/77), unblocked since PR #73 merged.

### Testing→main squash history gap (bluefin only)

`promote-testing-to-main.yml` squash-merges `testing → main`. Because the feature PRs were already squash-merged into `testing`, the squash on `main` creates a new SHA — the graphs diverge. Every subsequent sync requires a merge commit to reconnect them, making the promotion PR show the full accumulated history (50+ commits) instead of just the new work.

This is a known gap tracked in [#368](https://github.com/projectbluefin/bluefin/issues/368). The long-term fix (per [common#516](https://github.com/projectbluefin/common/issues/516)) is to replace the git-branch PR with branch fast-forward only, aligning with the dakota model.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `startup_failure` with zero jobs | unsupported permissions scope in that environment | compare `permissions:` with a known-good upstream run |
| `startup_failure` — `promote-to-stable` waits but workflow never starts | `environment: production` with `branch_policy: protected_branches: true` — rulesets are **not** recognized as classic branch protection by environment deployment policies | Switch the `production` environment to `custom_branch_policies: true` and explicitly add `main`: `gh api repos/projectbluefin/bluefin/environments/production -X PUT --field "deployment_branch_policy[custom_branch_policies]=true" --field "deployment_branch_policy[protected_branches]=false"` then `gh api repos/projectbluefin/bluefin/environments/production/deployment-branch-policies -X POST --field "name=main"` |
| `startup_failure` — workflow that calls `generate-release.yml` | `generate-release.yml` moved to `projectbluefin/actions` as an external reusable workflow | **`generate-release.yml` must remain a LOCAL workflow in this repo.** External cross-repo `workflow_call` reusable workflows cause `startup_failure` in `weekly-testing-promotion.yml` even when actionlint passes and the SHA is reachable. This may be a GitHub bug — do not attempt to centralize it again without testing first. |
| `startup_failure` — caller passes unknown `with:` inputs to `generate-release.yml` | Extra undeclared inputs in `with:` block for a `workflow_call` job cause startup validation failure | Match the `with:` inputs exactly to the callee's declared `inputs:` block; remove any keys not declared in the callee |
| `workflow_dispatch` returns HTTP 422 "secret name 'github_token' can not be used" | GitHub (enforced 2026-06-07) now blocks `github_token` as a `workflow_call` secret name — it collides with the system reserved name | Replace `secrets: { github_token: ... }` with no secrets block; use `github.token` directly inside the callee workflow |
| Testing Images runner timeout / job cancelled after 20+ min | Syft SBOM scan running for testing stream — both outer SBOM steps AND `sign-and-publish` internal Syft each scan the full image | Ensure `reusable-build.yml` has `stream_name != 'testing'` guard on all 4 outer SBOM steps AND passes `generate-sbom: false` to `sign-and-publish` for testing. Fixed in actions#123 + actions#124. |
| `No SBOM referrer found` in release generation | testing stream skips SBOM; promoted images lack signed SBOMs | allow missing SBOMs for diff generation and use intersection-only comparisons |
| promotion says no passing e2e for current SHA | `post-testing-e2e` has not passed the locked `main` commit | wait or rerun after e2e completes |
| required check is skipped | path filter skipped the workflow | verify whether skipped is intentional for that workflow |
| Renovate PR did not automerge | PR lookup missed mergeraptor author, or `testing` branch protection not set up | accept both `renovate[bot]` and `app/mergeraptor` in jq filter; ensure `testing` has branch protection with `validate` required check and `allow_auto_merge=true` at repo level |
| Weekly promotion cannot find digest artifact | artifact expired before Tuesday promotion window | push fresh commit to `main` to regenerate artifact |
| Cosign sign/verify fails | Sigstore outage or key rotation | check `check-cosign-key-rotation.yml` issues; retry after Sigstore recovers |
| COPR health monitor reports "no succeeded build" | COPR API changed response format — `latest_succeeded_build` moved to `builds.latest_succeeded` | Verify with raw API: `curl "https://copr.fedorainfracloud.org/api_3/package?ownername=X&projectname=Y&packagename=Z&with_latest_succeeded_build=True"` — if `builds.latest_succeeded` is present the repo is healthy; the monitor handles both formats |
| `validate` passes but enqueue returns "Required status check is expected" | `strict_required_status_checks_policy: true` — `testing` is behind `main` | `sync-main-to-testing.yml` handles this automatically after each promotion; if stuck, manually run `git merge projectbluefin/main` on `testing` and push |
| PR targeting `main` has no `validate` CI run | `pr-validation.yml` only triggered on `testing` (pre-fix state) | `pr-validation.yml` must list both `testing` and `main` in `branches:`; verify the workflow on `main` branch has been updated |

## Non-obvious patterns

- `post-testing-e2e.yml` is the continuous gate; weekly promotion assumes it already passed on the exact `main` SHA
- A skipped workflow can still satisfy a required check if GitHub considers it skipped-by-filter
- Stable release generation depends on SBOM assets existing for the images being diffed — testing stream skips SBOM generation; promoted images lack signed SBOMs until a separate SBOM pass runs
- Bluefin docs-only changes often skip image builds due to path filters; that is usually expected
- **`testing` branch has branch protection** — required status check: `validate`. `allow_auto_merge` enabled at repo level. `gh pr merge --auto --squash` works. No merge queue.
- **`main` branch has a merge queue (ruleset 17070404)** — required approvals: 1. Required check: `validate` (integration_id 15368). Merge method: squash. `strict_required_status_checks_policy: true` — the `validate` check must have passed against a HEAD that is fully up-to-date with `main` before enqueue is accepted. Enqueue via GraphQL:
  ```bash
  NODE_ID=$(gh pr view $PR --repo projectbluefin/bluefin --json id --jq .id)
  gh api graphql -f query="mutation { enqueuePullRequest(input: { pullRequestId: \"${NODE_ID}\" }) { mergeQueueEntry { id position } } }"
  ```
  If enqueue returns `"Required status check ... is expected."` despite validate passing, `testing` is behind `main` — sync first (see below). Org admins can bypass: `gh pr merge --squash --admin`.
- **`testing`/`main` branch sync — automated:** `sync-main-to-testing.yml` fires on every push to `main` and merges `main` → `testing` automatically. Manual sync is only needed if the workflow aborts due to a direct push to `main` that severs the merge base (CONFLICTING case — see "Testing→main squash history gap" above).
- **E2E (`testsuite` job) only runs on `merge_group`** — the `testsuite` job in `pr-validation.yml` has a hard `if: github.event_name == 'merge_group'` guard. There is no `detect-changes` conditional; the guard is unconditional. Per-push PR CI is fast validate + unit-tests only (~2 min). Do not add E2E to per-push PR jobs — each push triggering a 10-min QEMU boot is wasteful and blocks Renovate automerge.
- **Unit tests live in `tests/unit/`, not `build_files/`** — `build_files/**` is in the detect-changes image path filter; placing test files there causes every PR push to trigger image builds and E2E. Test files belong in `tests/unit/` where they are invisible to the image path filter.
- **`just test-unit` runs bats unit tests** — calls `bats tests/unit/`. The CI `unit-tests` job invokes `bats` directly (not `just`) because `just` is not available on a bare `ubuntu-latest` runner without the `setup-runner` composite action. Test files: `package-lib_test.bats`, `validate-repos_test.bats`, `copr-helpers_test.bats`.
- **Vulnerability scans must use the build digest, not a mutable tag.** `vulnerability-scan.yml` downloads `image-digest-{stream_name}-{brand_name}-{image_flavor}` from the triggering `workflow_run` and passes `image@sha256:...` to the scanner to avoid TOCTOU. Artifact names for the default bluefin build: `image-digest-testing-bluefin-main`, `image-digest-testing-bluefin-nvidia`.
- Weekly promotion uses retag-only (skopeo copy) — **no rebuild at promotion time**. `:stable` is set exclusively by `weekly-testing-promotion.yml`.
- Build callers do not pass `secrets: inherit` — `reusable-build.yml` only needs `GITHUB_TOKEN`, which is automatically available
- **`generate-release.yml` must be LOCAL** — never centralize it to `projectbluefin/actions`. External cross-repo `workflow_call` reusable workflows called from `weekly-testing-promotion.yml` cause `startup_failure` with 0 jobs starting, even when actionlint passes and the SHA is reachable. Root cause appears to be a GitHub validation interaction with the `production` environment and external callee. Verified 2026-06-07 after multiple failed centralization attempts.
- **`production` environment branch policy** — use `custom_branch_policies: true` with `main` explicitly added. The `protected_branches: true` policy does NOT recognize GitHub rulesets as branch protection (only classic branch protection rules count). A `main` branch protected only by a ruleset (merge queue) will cause `startup_failure` when any job uses `environment: production`.
- **`github_token` is a reserved workflow_call secret name** — GitHub enforces this (observed 2026-06-07). Using it returns HTTP 422 at dispatch time. Use `github.token` directly inside the callee instead.

## Shared actions architecture (projectbluefin/actions)

Common CI/CD logic lives in reusable GitHub Actions at **https://github.com/projectbluefin/actions** (current release: `v1`). These actions serve bluefin, aurora, bazzite, and any bootc image builder.

| Action | Status | Purpose |
|---|---|---|
| `bootc-build/setup-runner` | ✅ released on `v1` | Update podman from Ubuntu resolute, BTRFS mount, install just/cosign/oras/syft |
| `bootc-build/dnf-cache` | ✅ released on `v1` | Restore/save buildah cache with chmod 777 workaround |
| `bootc-build/ghcr-cleanup` | ✅ released on `v1` | Parameterized GHCR image retention |
| `bootc-build/preflight` | ✅ released on `v1` | Validate registry auth, normalize image refs, check required secrets |
| `bootc-build/detect-changes` | ✅ released on `v1` | Detect changed paths; compute image-flavor build matrix (`image_flavors`, `should_build`) |
| `bootc-build/validate-pr` | ✅ released on `v1` | PR validation: just check, shellcheck, hadolint, pre-commit — all tool pins live here |
| `bootc-build/push-image` | ✅ released on `v1` | Push once + skopeo copy for alias tags, digest capture |
| `bootc-build/sign-and-publish` | ✅ released on `v1` | Cosign sign (keyless or key-based) + Syft SBOM + ORAS attach + attestation |
| `bootc-build/rechunk` | ✅ released on `v1` | rpm-ostree chunkah rechunking with delta support |
| `bootc-build/generate-tags` | ✅ released on `v1` | Produce OCI tags from branch, date, Fedora version |
| `bootc-build/generate-release` | 🔲 planned | Changelog from RPM diff + SBOM comparison |

### Caller pinning rule

Workflow consumers in this repo pin `projectbluefin/actions` references to a full commit SHA and keep the release channel in a trailing comment:

```yaml
- uses: projectbluefin/actions/bootc-build/setup-runner@13e3593568d87cfe075a86e3995930e350f8c5ea # v1
```

Floating `@v1` tags are blocked by the repo's `no-floating-action-tags` pre-commit hook. The `# v1` comment is the stable contract; the SHA is the actual pin that Renovate updates.

### Migration pattern

Replace inline workflow steps with action calls:
```yaml
# Before: 15-line inline step
- name: Set up runner
  run: |
    sudo apt-get install ...
    sudo systemctl ...

# After: single action call
- uses: projectbluefin/actions/bootc-build/setup-runner@<SHA> # v1
  with:
    podman-version: "5.4"
```

### Design decisions

- Each action is independently consumable (no monolithic action bundle)
- Signing mode is an input (`keyless` or `key-based`), not hardcoded
- Consumer repos pin SHAs; Renovate tracks updates via the `github-actions` manager and preserves the `# v1` release-channel comment
- The full catalog and authoring guide lives at **https://github.com/projectbluefin/actions/tree/main/docs/skills**

### CI fix workflow for agents

When you encounter a CI issue that involves duplicated inline steps, path-filter logic, or pinned third-party actions in `.github/workflows/`, check whether the fix belongs in `projectbluefin/actions` first:

| Belongs in `projectbluefin/actions` | Stays in this repo |
|---|---|
| Shared step sequences (validate-pr, detect-changes) | Caller permissions scoping |
| Third-party action pins (hadolint, install-action, paths-filter) | `reusable-build.yml` caller inputs |
| Logic used in ≥2 workflows or ≥2 consumer repos | Repo-specific Justfile recipes |
| Path-filter definitions shared across workflows | Workflow scheduling, triggers, concurrency |

**Correct sequence when a fix belongs in `projectbluefin/actions`:**

1. Open a PR in `projectbluefin/actions` on a feature branch
2. Open a draft PR here pinned to the feature branch SHA (e.g. `projectbluefin/actions/bootc-build/detect-changes@<SHA>`)
3. CI must pass on this draft PR before the actions PR merges
4. After the actions PR merges, update this repo to the released `v1` SHA (keep the trailing `# v1` comment)

**Release-action consumer validation pattern:** if the shared action under test expects a semver tag or a `cliff.toml` but this repo does not ship them, add a draft-only manual workflow on the validation branch that creates a temporary local semver tag plus a temporary cliff config before calling the pinned shared action SHA. Link that workflow run in the actions PR as consumer-validation evidence.

Never duplicate an existing shared action inline — doing so creates a second Renovate pin that drifts independently.

## Hard rules for agents

- **PRs always target `testing`.** Never `main`. If you open a PR targeting `main`, close it and re-open.
- **Never add shared CI logic to `.github/` or `common`.** New reusable actions go in `projectbluefin/actions` only. See "CI fix workflow for agents" above for the correct sequence.
- **Never inline a third-party action that is already wrapped in `projectbluefin/actions`.** Use the shared action instead; duplicating the pin creates Renovate drift.
- **Bluefin workflow files are thin callers.** Local workflow edits should usually stop at triggers, permissions, concurrency, repo-specific constraints, and inputs to shared actions/workflows.
- **Workflow behavior changes must update `docs/skills/ci.md` in the same PR.** `skill-drift.yml` now runs on PRs to `testing` to enforce this on the real landing branch.
- **Read the actual workflow files before writing about them.** Stored memory about tags, steps, or behavior can be stale. Open the file and verify.
- **PATs are forbidden in projectbluefin repos.** Never add `RENOVATE_TOKEN` or any PAT secret. Renovate uses GitHub App auth via `projectbluefin/renovate-config`. Trigger Renovate: `gh workflow run "Renovate Self-Hosted" --repo projectbluefin/renovate-config`
- **No personal tool artifacts in community files.** This repo is shared; do not include powerlevel ratings, personal skill patterns, or client-specific references in `docs/`.

## Reference patterns

### PR rechunk guard requires a PR-only OCI export step

When adding `if: github.event_name != 'pull_request'` to the rechunk step, the "Upload OCI dir as Artifact" step breaks on PRs because `${{ env.IMAGE_NAME }}_build` (the rechunk output dir) no longer exists. Fix: add a PR-only step before the upload that exports the un-rechunked image:

```yaml
- name: Export image to OCI dir (PR only)
  if: github.event_name == 'pull_request'
  shell: bash
  run: |
    mkdir -p ${{ env.IMAGE_NAME }}_build
    sudo podman save --format oci-dir -o ${{ env.IMAGE_NAME }}_build \
      ${{ env.IMAGE_NAME }}:${{ env.DEFAULT_TAG }}
```

### skopeo copy for alias tags

`skopeo copy docker://... docker://...` needs the registry to be authenticated. The `Login to GitHub Container Registry` step must run before the push block (it already does in reusable-build.yml). No separate login needed for skopeo — it uses the credential store populated by `podman login`.

### `just check` in build matrix is redundant

`pr-validation.yml` already runs `just check` as a required check before merge. Running it in every matrix cell wastes ~60-120s per build with zero added value. Remove it from `reusable-build.yml`; keep it only in `pr-validation.yml`.

### Security posture — verified-good

Full adversarial review of all 23 workflow files completed. All findings resolved. Current verified-good state:

**Verified-good — do not remove:**
- All action pins use SHA (not floating tags)
- Workflow and job-level `permissions` scoped to minimum required
- Build callers do not use `secrets: inherit`
- `/e2e` dispatch gated to write/maintain/admin collaborators only
- Shell injection protected via env-variable binding for PR branch names
- GitHub App tokens (not PATs) for cherry-pick workflow
- OSSF Scorecard + Grype scanning active
- Weekly cosign key rotation detection (`check-cosign-key-rotation.yml`)
