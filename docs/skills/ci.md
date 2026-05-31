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

## Workflow map

| Workflow | Purpose |
|---|---|
| `pr-validation.yml` | PR gate on `testing` |
| `build-image-testing.yml` | build testing images from `main` |
| `post-testing-e2e.yml` | smoke-test current `main` testing image |
| `weekly-testing-promotion.yml` | promote tested `main` to `latest` + `stable` |
| `build-image-stable.yml` | build `stable` images |
| `build-image-latest-main.yml` | build `latest` images |
| `generate-release.yml` | create stable GitHub release text/assets |
| `renovate-automerge.yml` | auto-merge passing Renovate PRs |
| `validate-renovate.yml` | validate `.github/renovate.json5` |

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
| `No SBOM referrer found` in release generation | one side of the diff has no attached SBOM | allow missing SBOMs for diff generation and use intersection-only comparisons |
| promotion says no passing e2e for current SHA | `post-testing-e2e` has not passed the locked `main` commit | wait or rerun after e2e completes |
| required check is skipped | path filter skipped the workflow | verify whether skipped is intentional for that workflow |
| Renovate PR did not automerge | PR lookup missed mergeraptor author or wrong base branch | accept both Renovate and mergeraptor authors; verify branch targeting |

## Non-obvious patterns

- `post-testing-e2e.yml` is the continuous gate; weekly promotion assumes it already passed on the exact `main` SHA
- A skipped workflow can still satisfy a required check if GitHub considers it skipped-by-filter
- Stable release generation depends on SBOM assets existing for the images being diffed
- Bluefin docs-only changes often skip image builds due to path filters; that is usually expected

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
| `bootc-build/generate-tags` | 🔲 planned | Produce OCI tags from branch, date, Fedora version |
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
