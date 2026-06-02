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

## Workflow map (complete — 23 workflows)

| Workflow | Trigger | Purpose |
|---|---|---|
| `pr-validation.yml` | PRs to `testing`, merge_group | Fast gate: just check, shellcheck, pre-commit, e2e smoke |
| `pr-smoke.yml` | PRs touching build files | Full build + smoke test |
| `build-image-testing.yml` | Push to `main`, dispatch | Testing image builds via centralized `projectbluefin/actions` workflow |
| `post-testing-e2e.yml` | Testing build on `main` | Smoke+common continuous e2e gate |
| `weekly-testing-promotion.yml` | Tuesday 06:00 UTC | Full e2e → retag to :stable/:latest |
| `build-image-stable.yml` | Push to `stable`, dispatch | Stable rebuild |
| `build-image-latest-main.yml` | Push to `latest`, dispatch | Latest rebuild |
| `build-images.yml` | Manual dispatch | Rebuild all streams |
| ~~`reusable-build.yml`~~ (deleted) | Replaced by `projectbluefin/actions/.github/workflows/reusable-build.yml` | **All build callers now use the centralized workflow — no local copy** |
| `run-testsuite.yml` | Called by all e2e workflows | **Canonical testsuite wrapper — always use this, never e2e.yml directly** |
| `nightly.yml` | 02:00 UTC daily | smoke+common+vanilla-gnome against :latest |
| `vulnerability-scan.yml` | Testing build + weekly | Grype → SARIF to Security tab |
| `renovate-automerge.yml` | PR Validation / PR Smoke success | Auto-merge Renovate/mergeraptor by risk tier |
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

1. Push to `main`
2. `build-image-testing.yml` publishes testing images
3. `post-testing-e2e.yml` smoke-tests that exact digest
4. `weekly-testing-promotion.yml` verifies the same `main` SHA still passed e2e
5. Promotion fast-forwards `latest` and `stable`
6. Branch-specific build workflows rebuild those streams

If `main` advanced during promotion, the workflow aborts on purpose.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `startup_failure` with zero jobs | unsupported permissions scope in that environment | compare `permissions:` with a known-good upstream run |
| `No SBOM referrer found` in release generation | one side of the diff has no attached SBOM (testing stream skips SBOM — #213) | allow missing SBOMs for diff generation and use intersection-only comparisons |
| promotion says no passing e2e for current SHA | `post-testing-e2e` has not passed the locked `main` commit | wait or rerun after e2e completes |
| required check is skipped | path filter skipped the workflow | verify whether skipped is intentional for that workflow |
| Renovate PR did not automerge | PR lookup missed mergeraptor author or wrong base branch | accept both `renovate[bot]` and `app/mergeraptor` in jq filter; verify branch targeting `testing` |
| Weekly promotion cannot find digest artifact | Artifact expired (1-day retention, #212) | Push fresh commit to `main` to regenerate artifact |
| Cosign sign/verify fails | Sigstore outage or base image cosign verify is non-fatal (#214) | Check `check-cosign-key-rotation.yml` issues; verify Justfile cosign steps are fatal |
| Architecture fromJson() parse error | Architecture input default uses single quotes: `"['x86_64']"` (#210) | Pass architecture explicitly or fix default to `'["x86_64"]'` |

## Non-obvious patterns

- `post-testing-e2e.yml` is the continuous gate; weekly promotion assumes it already passed on the exact `main` SHA
- A skipped workflow can still satisfy a required check if GitHub considers it skipped-by-filter
- Stable release generation depends on SBOM assets existing for the images being diffed — testing stream skips SBOM, so promoted images lack them until #213 is fixed
- Bluefin docs-only changes often skip image builds due to path filters; that is usually expected
- **Testsuite pin lives in `run-testsuite.yml` only** — all other workflows must call this wrapper; never call `projectbluefin/testsuite/.github/workflows/e2e.yml` directly
- Weekly promotion uses retag-only (skopeo copy) for the canonical path; a parallel rebuild pathway also exists via branch push (dual provenance — see #225)
- `secrets: inherit` in build callers passes ALL org secrets to reusable-build; only `GITHUB_TOKEN` is needed (#220)

## Shared actions architecture (projectbluefin/actions)

Common CI/CD logic lives in reusable GitHub Actions at **https://github.com/projectbluefin/actions** (current release: `v1`). These actions serve bluefin, aurora, bazzite, and any bootc image builder.

| Action | Status | Purpose |
|---|---|---|
| `bootc-build/setup-runner` | ✅ live `@v1` | Update podman from Ubuntu resolute, BTRFS mount, install just/cosign/oras/syft |
| `bootc-build/dnf-cache` | ✅ live `@v1` | Restore/save buildah cache with chmod 777 workaround |
| `bootc-build/ghcr-cleanup` | ✅ live `@v1` | Parameterized GHCR image retention |
| `bootc-build/preflight` | ✅ live `@v1` | Validate registry auth, normalize image refs, check required secrets |
| `bootc-build/push-image` | ✅ live `@v1` | Push once + skopeo copy for alias tags, digest capture |
| `bootc-build/sign-and-publish` | ✅ live `@v1` | Cosign sign (keyless or key-based) + Syft SBOM + ORAS attach + attestation |
| `bootc-build/rechunk` | ✅ live `@v1` | rpm-ostree chunkah rechunking with delta support |
| `bootc-build/generate-tags` | ✅ live `@v1` | Produce OCI tags from branch, date, Fedora version |
| `bootc-build/generate-release` | 🔲 planned | Changelog from RPM diff + SBOM comparison |

### Migration pattern

Replace inline workflow steps with action calls:
```yaml
# Before: 15-line inline step
- name: Set up runner
  run: |
    sudo apt-get install ...
    sudo systemctl ...

# After: single action call
- uses: projectbluefin/actions/bootc-build/setup-runner@v1
  with:
    podman-version: "5.4"
```

### Design decisions

- Each action is independently consumable (no monolithic action bundle)
- Signing mode is an input (`keyless` or `key-based`), not hardcoded
- Actions pin to `@v1` semver tags; Renovate tracks updates via `github-actions` manager
- The `projectbluefin/actions` repo is live at https://github.com/projectbluefin/actions
- Pin consuming workflows to `@v1`; Renovate tracks updates via `github-actions` manager
- P2 actions (`generate-tags`, `generate-release`) are tracked in bluefin issue #134

## Hard rules for agents

- **PRs always target `testing`.** Never `main`. If you open a PR targeting `main`, close it and re-open.
- **Never add shared CI logic to `.github/` or `common`.** New reusable actions go in `projectbluefin/actions` only.
- **Read the actual workflow files before writing about them.** Stored memory about tags, steps, or behavior can be stale. Open the file and verify.
- **PATs are forbidden in projectbluefin repos.** Never add `RENOVATE_TOKEN` or any PAT secret. Renovate uses GitHub App auth via `projectbluefin/renovate-config`. Trigger Renovate: `gh workflow run "Renovate Self-Hosted" --repo projectbluefin/renovate-config`
- **No personal tool artifacts in community files.** This repo is shared; do not include powerlevel ratings, personal skill patterns, or client-specific references in `docs/`.

## Lessons learned

### PR rechunk guard requires a PR-only OCI export step (2026-05-31)

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

### skopeo copy for alias tags requires registry login before the push step

`skopeo copy docker://... docker://...` needs the registry to be authenticated. The `Login to GitHub Container Registry` step must run before the push block (it already does in reusable-build.yml). No separate login needed for skopeo — it uses the credential store populated by `podman login`.

### `just check` in build matrix is redundant

`pr-validation.yml` already runs `just check` as a required check before merge. Running it in every matrix cell wastes ~60-120s per build with zero added value. Remove it from `reusable-build.yml`; keep it only in `pr-validation.yml`.

### Pre-production security audit — 14 tracked findings (2026-06-01)

Full adversarial review of all 23 workflow files. Epic: **#209**. Sub-issues: **#210–#215, #218–#225**.

**Blocking (P1) — fix before relying on production pipeline:**

| Issue | File | Finding |
|---|---|---|
| #210 | `reusable-build.yml` L26 | Architecture default `"['x86_64']"` — invalid JSON (single quotes). Fix: `'["x86_64"]'` |
| #211 | `weekly-testing-promotion.yml` | Tests only `bluefin-main`, promotes ALL flavors incl. `nvidia-open` without e2e coverage |
| #212 | `reusable-build.yml` L515 | Digest artifact retention `1d`. Weekly Tuesday run fails if no push in 24h. Raise to `7d` |
| #213 | `reusable-build.yml` L209+ | Testing stream skips SBOM (`if: inputs.stream_name != 'testing'`). Promoted :stable/:latest lack signed SBOMs. Breaks `generate-release.yml` |
| #214 | `Justfile` | Base image cosign verify is `\|\| echo "WARNING...Continuing"` — non-fatal. Compromised base flows through |
| #215 | `Justfile` | Cosign bootstrapped from `cgr.dev/chainguard/cosign:latest` (unverified tag). Use SHA-pinned `sigstore/cosign-installer` instead |

**Non-blocking (P2):**

| Issue | File | Finding |
|---|---|---|
| #218 | `weekly-testing-promotion.yml` | No `cosign verify` before retag — unsigned digest can reach production |
| #219 | `weekly-testing-promotion.yml` L12-15 | `contents/actions/packages: write` at workflow level — over-broad for read-only jobs |
| #220 | `build-image-*.yml` | All callers use `secrets: inherit` — only `GITHUB_TOKEN` needed |
| #221 | `vulnerability-scan.yml` L48 | Scans `:testing` tag not build digest (TOCTOU) |
| #222 | `pr-smoke.yml` L83-87 | PR builds push under official `ghcr.io/projectbluefin/` namespace |
| #223 | `pr-validation.yml` L55 | Stale testsuite SHA `5d273131` (canonical: `969d4713` in `run-testsuite.yml`); bypasses wrapper |
| #224 | `pr-validation.yml` L28 | `pip install pre-commit` unpinned |
| #225 | `build-image-stable.yml` | Parallel rebuild pathway coexists with retag-only promotion (dual provenance) — needs maintainer decision |

**Verified-good — do not remove:**
- All action pins use SHA (not floating tags)
- `permissions: {}` at workflow level + per-job escalation in `reusable-build.yml`
- `/e2e` dispatch gated to write/maintain/admin collaborators only
- Shell injection protected via env-variable binding for PR branch names
- GitHub App tokens (not PATs) for cherry-pick workflow
- OSSF Scorecard + Grype scanning active
- Weekly cosign key rotation detection (`check-cosign-key-rotation.yml`)
