# Bluefin CI reference

## Pipeline overview

Bluefin's CI is split between PR validation, image builds, post-build e2e, weekly promotion, and repo automation.

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-validation.yml` | PRs to `testing`, `merge_group` | Fast validation: `just check`, `shellcheck`, `pre-commit` |
| `build-image-testing.yml` | Push to `main`, `merge_group`, dispatch, workflow call | Builds testing images via centralized `projectbluefin/actions` workflow |
| `post-testing-e2e.yml` | Successful `Testing Images` workflow on `main` push | Downloads the testing digest and runs smoke tests in `projectbluefin/testsuite` |
| `weekly-testing-promotion.yml` | Tuesday 06:00 UTC, manual dispatch | Verifies e2e on current `main`, promotes `main` to `latest` + `stable`, triggers downstream builds |
| `build-image-stable.yml` | Push to `stable`, dispatch, workflow call | Builds stable images and then runs `generate-release.yml` |
| `build-image-latest-main.yml` | PR/push to `latest`, `merge_group`, dispatch | Builds latest images |
| `renovate-automerge.yml` | Successful `PR Validation — testsuite` workflow | Enables squash auto-merge for matching Renovate PRs |
| `bonedigger.yml` | Issue events, issue comments, daily schedule | Runs the Bluefin 🦖 issue lifecycle bot |

## Centralized actions (`projectbluefin/actions`)

Shared reusable workflows and composite actions for the Bluefin build pipeline live in [`projectbluefin/actions`](https://github.com/projectbluefin/actions). **Do not add new action pins inline in workflow files** — if the same action would be used in more than one workflow, it belongs in a composite action in `projectbluefin/actions`. This keeps Renovate updates centralised: one PR in `projectbluefin/actions` propagates to all consumers.

The internal `reusable-build.yml` has been deleted — all three stream callers delegate to the centralized workflow:

```yaml
uses: projectbluefin/actions/.github/workflows/reusable-build.yml@<SHA>
```

- Matrix: `bluefin`
- Flavors: `main`, `nvidia-open`
- Default architecture: `x86_64`
- Builds with `just build-ghcr`, then rechunks, retags, runs secureboot checks, and generates tags
- On non-PR events it pushes to GHCR, signs images with cosign, uploads SBOMs, and emits attestations
- On PR events it uploads a `.oci` artifact and prints bootc test instructions instead of pushing

### Available composite actions

| Action | Purpose |
|---|---|
| `bootc-build/setup-runner` | Update podman, BTRFS mount, install tools |
| `bootc-build/detect-changes` | Detect changed paths; compute `image_flavors` matrix for PR builds |
| `bootc-build/validate-pr` | PR validation: just check, shellcheck, hadolint, pre-commit (all tool pins live here) |
| `bootc-build/dnf-cache` | Restore/save buildah layer cache |
| `bootc-build/preflight` | Validate registry auth, normalize image refs |
| `bootc-build/push-image` | GHCR push with retry and digest capture |
| `bootc-build/sign-and-publish` | Cosign sign + SBOM + attestation |
| `bootc-build/rechunk` | rpm-ostree rechunking for OTA deltas |
| `bootc-build/generate-tags` | Generate OCI tags from stream, version, and event context |

See [`docs/skills/ci.md`](skills/ci.md) → "Shared actions architecture" for the full catalog and fix-first workflow.

## How PRs are validated

A normal Bluefin PR should target `testing`.

`pr-validation.yml` runs validation via the shared `bootc-build/validate-pr` action from `projectbluefin/actions`:

1. Install `just` (via `taiki-e/install-action`)
2. Install `shellcheck`
3. Install `pre-commit`
4. Run `just check`
5. Run `shellcheck build_files/**/*.sh`
6. Run `hadolint` on `Containerfile`
7. Run `pre-commit run --all-files`

This workflow is intentionally fast. It validates repo health without doing a full local-style container build. All tool pins (hadolint, install-action) live in `bootc-build/validate-pr` — Renovate bumps them once there, not per-workflow.

## How testing promotion works

There are two different branch roles to keep straight:

- **Contribution branch:** PRs land on `testing`
- **Image promotion branch flow in current workflows:** `main` → `latest` / `stable`

Current automation works like this:

1. A push to `main` runs `build-image-testing.yml`
2. `post-testing-e2e.yml` waits for that build, downloads `image-digest-testing-bluefin-main`, and runs the `smoke,common` suites from `projectbluefin/testsuite`
3. `weekly-testing-promotion.yml` (Tuesday 06:00 UTC) locks the current `main` SHA
4. It verifies `post-testing-e2e` already passed for that exact SHA
5. It reruns broader `developer,vanilla-gnome,software,common` suites against the locked digest
6. If `main` did not advance during testing, it retags all testing digests → `:latest` and `:stable` via skopeo copy (no rebuild)
7. Branch push triggers on `latest`/`stable` also rebuild from source (dual pathway — see #225)

The weekly promotion workflow refuses to promote untested code. It uses SHA-locked digests throughout, not mutable tags.

### Testsuite pin management

The canonical testsuite pin lives in **one place only**: `.github/workflows/run-testsuite.yml`. All other workflows must call this wrapper — never call `projectbluefin/testsuite/.github/workflows/e2e.yml` directly. Renovate maintains the single pin automatically.

```bash
# Check for drift — should return empty
grep -rn "projectbluefin/testsuite" .github/workflows/ | grep -v "run-testsuite.yml"
```

### SBOM / provenance chain

- **Testing builds:** SBOM generation is skipped (runner time budget)
- **Stable/latest direct builds:** Full SBOM via Syft → ORAS attach → cosign sign
- **Weekly promotion path:** Retags testing digests which lack SBOMs
- **Attestation:** `actions/attest` runs on all non-PR builds regardless of stream
- **SBOM verification:** `oras discover --format json ghcr.io/projectbluefin/IMAGE@DIGEST | jq '.referrers[] | select(.artifactType == "application/vnd.spdx+json")'`

## Renovate and automation notes

- `.github/renovate.json5` is configured with `baseBranchPatterns: ["testing"]`
- `renovate-automerge.yml` searches for matching PRs with `--base testing`
- Matches both `renovate[bot]` and `app/mergeraptor` — both login names appear in practice
- Risk-tiered: PRs with `renovate/high-risk` label wait for PR Smoke Test; low-risk merge after PR Validation
- If Renovate PRs stop auto-merging, verify the trigger workflow name matches (`PR Validation — testsuite` or `PR Smoke Test`) and that author filter includes both bot names

## Security model

### Supply chain

Every production image has:
1. **Base image verification:** cosign verify against `keys/fedora-ostree.pub` before build
2. **Cosign keyless signing:** OIDC-based via Sigstore Fulcio (`sigstore/cosign-installer@SHA`)
3. **Signature verification post-push:** `cosign verify --certificate-identity-regexp ...` runs immediately after push
4. **SBOM:** Syft-generated, ORAS-attached, cosign-signed (stable/latest stream only — see #213)
5. **GitHub Attestation:** `actions/attest` on all non-PR builds

### Key files

- `keys/fedora-ostree.pub` — vendored Fedora OSTree signing key
- `keys/projectbluefin-common.pub` — common layer signing key
- `keys/ublue-os-brew.pub` — brew layer signing key
- `check-cosign-key-rotation.yml` — weekly monitor, opens P1 issue on mismatch

### Known gaps

| Gap | Description |
|-----|-------------|
| Testing stream skips SBOM | Promoted `:stable`/`:latest` images lack signed SBOMs; `generate-release.yml` must tolerate missing referrers |
| Weekly promotion tests one flavor | Only `bluefin-main` is e2e-verified before all flavors are promoted |

## Build caching

`reusable-build.yml` uses two layers of caching to speed up matrix builds:

### DNF / buildah package cache

Each matrix job saves and restores `/var/tmp/buildah-cache-*` via `actions/cache`.

**Cache key format:**
```
{runner.os}-{architecture}-buildah-{image_flavor}-{image_name}-{fedora_version}
```
Example: `Linux-x86_64-buildah-main-bluefin-44`

The `image_flavor` segment (`main` / `nvidia-open`) is critical — without it, parallel jobs sharing the same image name write to the same key and GitHub's cache API rejects all-but-one save with "Unable to reserve cache, another job may be creating this cache".

**Restore-key fallback** (broadest-to-narrowest):
1. `Linux-x86_64-buildah-main-bluefin-44` (exact hit)
2. `Linux-x86_64-buildah-main-` (cross-image hit within same flavor)
3. `Linux-x86_64-buildah-` (cross-flavor hit)

**Permission workaround:** buildah creates cache dirs as root. A `cache-perms` step runs `sudo chmod 777 --recursive` on all `/var/tmp/buildah-cache-*` dirs so `actions/cache` (running as the runner user) can read them. The glob is important — buildah may create multiple numbered dirs (`-0`, `-1`, …).

**Cache writes are gated** — only non-PR, non-testing-stream builds write the cache (via `setup-cache` recipe in `Justfile`).

### OCI layer cache (`bluefin-cache`)

Separate from the DNF cache. Uses `ghcr.io/projectbluefin/bluefin-cache` for container layer caching via `--cache-from`/`--cache-to`. Only enabled if the registry package is public (probed with `skopeo inspect`). Refs must be **untagged** (Podman 5.x rejects tagged refs for cache operations).

### Cache budget

GitHub provides 10 GB per repo. With 4 flavor+image combinations each ~2-3 GB, the cache approaches the limit. `cache-maintenance.yml` runs weekly to prune entries older than 14 days or from deleted branches.

## Common failure modes

| Symptom | Likely cause | First fix to try |
|---|---|---|
| PR validation did not run | PR targeted the wrong base branch | Retarget the PR to `testing` |
| `just check` fails | Broken `Justfile` / `*.just` formatting | Run `just fix`, then rerun validation |
| Shellcheck fails | New shell logic in `build_files/**` is not portable/safe | Fix the script locally and rerun `shellcheck` |
| `pre-commit` fails | Formatting or repo policy hook failed | Run `pre-commit run --all-files` locally and apply the fixes |
| Post-testing e2e cannot find a digest | Artifact name or upstream build output changed | Verify `build-image-testing.yml` and `reusable-build.yml` still publish `image-digest-testing-bluefin-main` |
| Weekly promotion aborts because `main` advanced | New commits landed during e2e | Rerun `weekly-testing-promotion.yml` after e2e is green again |
| Weekly promotion cannot download digest artifact | Artifact expired before the Tuesday window | Trigger a fresh push to `main` to get a new artifact |
| Renovate auto-merge finds no PR | Author filter mismatch (renovate[bot] vs app/mergeraptor) | Check jq filter in `renovate-automerge.yml` includes both |
| `generate-release.yml` fails with "No SBOM referrer found" | Testing stream skips SBOM; promoted images lack referrers | See `allow_missing_sbom=True` pattern in skill Learnings |
| Cosign sign/verify fails | Sigstore Fulcio/Rekor outage or key rotation | Check `check-cosign-key-rotation.yml` issues; retry after Sigstore recovers |

## Complete workflow inventory

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-validation.yml` | PRs to `testing`, `merge_group` | Fast validation: `just check`, `shellcheck`, `pre-commit`, e2e smoke |
| `pr-smoke.yml` | PRs touching build files | Full image build + smoke test |
| `build-image-testing.yml` | Push to `main`, `merge_group`, dispatch | Builds testing images via `reusable-build.yml` |
| `post-testing-e2e.yml` | Successful `Testing Images` on `main` push | Smoke+common e2e gate; opens issue on failure |
| `weekly-testing-promotion.yml` | Tuesday 06:00 UTC, dispatch | Full e2e → retag testing digests to :latest/:stable |
| `build-image-stable.yml` | Push to `stable`, dispatch | Rebuild stable + generate release |
| `build-image-latest-main.yml` | Push/PR to `latest`, dispatch | Rebuild latest |
| `build-images.yml` | Manual dispatch only | Rebuild all streams |
| `nightly.yml` | 02:00 UTC daily | smoke+common+vanilla-gnome against :latest |
| `vulnerability-scan.yml` | Testing build + Monday 08:00 UTC | Grype scan → SARIF to Security tab |
| `renovate-automerge.yml` | Successful PR Validation or PR Smoke | Auto-merge Renovate/Mergeraptor PRs by risk tier |
| `e2e-dispatch.yml` | `/e2e` comment (write+ only) | Manual e2e trigger: builds PR → smoke+developer+vanilla-gnome |
| `generate-release.yml` | Stable build completion, dispatch | Creates GitHub Release with changelog + SBOMs |
| `copr-health-monitor.yml` | Daily 07:00 UTC | Checks COPR repo staleness; opens issue on failure |
| `check-cosign-key-rotation.yml` | Monday 06:00 UTC | Compares vendored keys to upstream; opens P1 issue on mismatch |
| `cache-maintenance.yml` | Monday 06:00 UTC | Prunes GHA caches from deleted branches or >14d inactive |
| `clean.yml` | Sunday 00:15 UTC | Deletes GHCR images older than 90 days |
| `scorecard.yml` | Push to main, Tuesday weekly | OSSF Scorecard supply chain analysis |
| `cherry-pick-to-stable.yml` | PR closed with `cherry-pick` label | Backports to `stable` via GitHub App token |
| `bonedigger.yml` | Issue events, daily | Issue lifecycle bot |
| `moderator.yml` | Issues/comments opened | AI spam + AI-content detection |
| `validate-renovate.yml` | Renovate config PRs | Validates renovate.json5 syntax |
