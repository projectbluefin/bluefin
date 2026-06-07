# Bluefin CI reference

## Pipeline overview

Bluefin's CI is split between PR validation, image builds, post-build e2e, weekly promotion, and repo automation.

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-validation.yml` | PRs to `testing`, `merge_group` | Fast validation via `validate-pr@v1`: `just check`, `shellcheck`, `hadolint`, `pre-commit`, **bats unit tests** — **E2E only on `merge_group`** |
| `promote-testing-to-main.yml` | Push to `testing`, daily 23:00 UTC, manual dispatch | Upserts the long-lived `testing` → `main` promotion PR and enables squash auto-merge |
| `sync-main-to-testing.yml` | Push to `main` | Merges `main` back into `testing` after each squash-merge promotion to prevent the next PR from opening `BEHIND` |
| `build-image-testing.yml` | Push to `main`, `merge_group`, dispatch, workflow call | Builds testing images via centralized `projectbluefin/actions` workflow |
| `post-testing-e2e.yml` | Successful `Testing Images` workflow on `main` push | Downloads the testing digest and runs smoke tests in `projectbluefin/testsuite` |
| `weekly-testing-promotion.yml` | Tuesday 06:00 UTC, manual dispatch | Verifies e2e on current `main`, promotes `main` to `latest` + `stable`, triggers downstream builds |
| `build-image-stable.yml` | Push to `stable`, dispatch, workflow call | Builds stable images and then runs `generate-release.yml` |
| `build-image-latest-main.yml` | PR/push to `latest`, `merge_group`, dispatch | Builds latest images |
| `renovate-automerge.yml` | Successful `PR Validation — testsuite` | Enables squash auto-merge (`gh pr merge --auto --squash`) for Renovate/mergeraptor PRs |
| `bonedigger.yml` | Issue events, issue comments, daily schedule | Runs the Bluefin 🦖 issue lifecycle bot |

## Centralized actions (`projectbluefin/actions`)

Shared reusable workflows and composite actions live in [`projectbluefin/actions`](https://github.com/projectbluefin/actions). **Do not add new action pins inline in workflow files** — if the same action would be used in more than one workflow, it belongs in a composite action in `projectbluefin/actions`. This keeps Renovate updates centralised: one PR in `projectbluefin/actions` propagates to all consumers.

### Architecture rule

| Location | Purpose |
|---|---|
| `projectbluefin/actions/bootc-build/` | Shared composite actions (setup-runner, detect-changes, rechunk, …) |
| `projectbluefin/actions/.github/workflows/` | Shared reusable workflows (reusable-build.yml) |
| `.github/actions/` (this repo) | **Repo-specific** helpers only — must not duplicate what `projectbluefin/actions` already provides |
| Inline `uses:` in workflow YAML | Only for actions used exactly once in this repo and not shared across the org |

### Referencing shared actions

Pin to a full commit SHA during development; update to `@v1` after the action PR merges and the maintainer advances the tag:

```yaml
# During development / before v1 tag moves:
uses: projectbluefin/actions/bootc-build/detect-changes@4387ca8dfc2f33db48b30e3ccc2011f1df5f8b10

# After v1 is released:
uses: projectbluefin/actions/bootc-build/detect-changes@v1
```

Renovate tracks SHA pins automatically (`config:best-practices` includes `github-actions` manager).

### Available shared components

| Name | Path | Purpose |
|---|---|---|
| `setup-runner` | `bootc-build/setup-runner` | Install just, buildah, podman, skopeo, oras; set up storage |
| `detect-changes` | `bootc-build/detect-changes` | Path-filter: image_changed, nvidia_changed, image_flavors |
| `dnf-cache` | `bootc-build/dnf-cache` | Restore/save DNF build cache |
| `ghcr-cleanup` | `bootc-build/ghcr-cleanup` | Delete old images from GHCR |
| `preflight` | `bootc-build/preflight` | Pre-build cosign verify, key checks |
| `push-image` | `bootc-build/push-image` | Push OCI image to GHCR |
| `sign-and-publish` | `bootc-build/sign-and-publish` | Cosign sign, SBOM attach, attest |
| `rechunk` | `bootc-build/rechunk` | rpm-ostree rechunker step |
| `reusable-build.yml` | `.github/workflows/` | Core image build engine (all stream callers use this) |

### Tracked gaps in centralisation

| Gap | Issue |
|---|---|
| `github/codeql-action/upload-sarif` SHA drifted between scorecard.yml and vulnerability-scan.yml | #251 |
| `actions/checkout` v4.3.1 in check-cosign-key-rotation.yml vs v6 everywhere else | #252 |
| `.github/actions/bootstrap-just` duplicates setup-runner's `just` install | #253 |
| pr-validation.yml validate job (hadolint/shellcheck/pre-commit) should be a shared action | #254 |

### Build workflow

The shared image build engine is at `.github/workflows/reusable-build.yml` in `projectbluefin/actions`. The `testing` and `main` stream callers delegate to it:

```yaml
uses: projectbluefin/actions/.github/workflows/reusable-build.yml@<SHA>
```

> **⚠️ `stable` branch exception:** The `stable` branch maintains its **own local copy** of `.github/workflows/reusable-build.yml` (a diverged legacy version). `build-image-stable.yml` calls `uses: ./.github/workflows/reusable-build.yml` (self-referential). Fixes landed in `projectbluefin/actions` do NOT automatically apply to `stable`. When CI breaks on `stable`, hotfix directly on the `stable` branch — cherry-picking from `testing` will conflict because `testing` does not have that file.

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

`pr-validation.yml` runs two parallel jobs on every PR push:

**`validate` job** — via the shared `bootc-build/validate-pr` action from `projectbluefin/actions`:
1. Install `just` (via `taiki-e/install-action`)
2. Install `shellcheck`
3. Install `pre-commit`
4. Run `just check`
5. Run `shellcheck build_files/**/*.sh`
6. Run `hadolint` on `Containerfile`
7. Run `pre-commit run --all-files`

**`unit-tests` job** — fast bats tests for shared shell libraries:
1. Install `bats` (`apt-get install bats`)
2. Run `bats tests/unit/package-lib_test.bats`

**`testsuite` job (E2E smoke)** — runs **only on `merge_group`**, never on PR pushes:
- Uses `run-testsuite.yml` with `suites: smoke`
- This gates the actual merge; individual PR commits are not blocked waiting for full e2e

This keeps PR feedback fast (~2-3 min) while still gating every merge to `testing` with a smoke test.

> **Note:** `tests/unit/` is intentionally excluded from image path filters. Adding test files to `tests/unit/` does not trigger image builds or E2E on PRs.

## How testing promotion works

There are three different branch roles to keep straight:

- **Contribution branch:** PRs land on `testing`
- **Testing image branch:** `main` builds the `:testing` stream
- **Production promotion branch flow:** `main` → `latest` / `stable`

Current automation works like this:

1. A push to `testing` runs `promote-testing-to-main.yml`
2. That workflow compares the `testing` and `main` tree hashes, upserts a single `testing` → `main` PR, and enables squash auto-merge
3. The comparison is tree-based rather than `git log main..testing`, so squash merges do not cause already-promoted commits to be re-proposed
4. The workflow uses the Bluefin bot GitHub App token so the `testing` → `main` PR fires normal `pull_request` CI before merge queue entry
5. Once the promotion PR merges to `main`, `build-image-testing.yml` builds the testing images
5a. `sync-main-to-testing.yml` fires on that same push to `main`, merges `main` back into `testing`, and keeps the branches in sync so the next promotion PR is not `BEHIND`
6. `post-testing-e2e.yml` waits for that build, downloads `image-digest-testing-bluefin-main`, and runs the `smoke,common` suites from `projectbluefin/testsuite`
7. `weekly-testing-promotion.yml` (Tuesday 06:00 UTC) locks the current `main` SHA
8. It verifies `post-testing-e2e` already passed for that exact SHA
9. It reruns broader `developer,vanilla-gnome,software,common` suites against the locked digest
10. If `main` did not advance during testing, it retags all testing digests → `:latest` and `:stable` via skopeo copy (no rebuild)
11. Branch push triggers on `latest`/`stable` also rebuild from source (dual pathway — see #225)

The weekly promotion workflow refuses to promote untested code. It uses SHA-locked digests throughout, not mutable tags.

### Squash-merge history gap — promotion PR shows CONFLICTING

**Symptom:** The auto-created `testing` → `main` promotion PR shows "This branch has conflicts" even though the file changes do not actually conflict.

**Root cause:** After a squash merge, `testing` and `main` share no git merge base. Any commit pushed directly to `main` (bypassing `testing`) severs the common ancestor entirely. GitHub marks the PR as CONFLICTING and refuses to merge it — even `gh pr merge --admin` is blocked.

**Fix:**

```bash
git checkout testing && git pull projectbluefin testing --ff-only
git merge projectbluefin/main --allow-unrelated-histories -s recursive -X ours \
  -m "ci: sync testing with main to resolve squash-merge history gap

<explain what commit landed directly on main and why>

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git push projectbluefin testing
```

The `-X ours` strategy keeps `testing`'s version for any file that exists on both sides (e.g. pinned SHAs in workflow files). After the push, `promote-testing-to-main.yml` fires and creates a fresh, mergeable promotion PR.

**Prevention:** Never push commits directly to `main` unless breaking a bootstrap deadlock. All changes go through `testing`.

### Testsuite pin management

The canonical testsuite pin lives in **one place only**: `.github/workflows/run-testsuite.yml`. All other workflows must call this wrapper — never call `projectbluefin/testsuite/.github/workflows/e2e.yml` directly. Renovate maintains the single pin automatically.

```bash
# Check for drift — should return empty
grep -rn "projectbluefin/testsuite" .github/workflows/ | grep -v "run-testsuite.yml"
```

### SBOM / provenance chain

- **Testing builds:** SBOM generation is skipped (runner time budget)
- **Stable/latest direct builds:** Full SBOM via Syft → ORAS attach → cosign sign
- **Weekly promotion path:** Retags testing digests which lack SBOMs; `generate-release.yml` falls back to a no-SBOM release — see #424
- **Attestation:** `actions/attest` runs on all non-PR builds regardless of stream
- **SBOM verification:** `oras discover --format json ghcr.io/projectbluefin/IMAGE@DIGEST | jq '.referrers[] | select(.artifactType == "application/vnd.spdx+json")'`

### Vulnerability scan — Trivy and the podman socket

`reusable-build.yml` builds images with `sudo podman build`, storing them in **root's** podman storage. Trivy runs as the runner user (uid 1001) and cannot reach root-owned images via the rootless socket (`/run/user/1001/podman/podman.sock`).

**Fix (already in place):** Before scanning, export the image to an OCI archive and point Trivy at that:

```yaml
- name: Export image for scanning
  run: sudo podman save --format oci-archive -o /tmp/scan-image.tar "$IMAGE_NAME:$DEFAULT_TAG"

- name: Scan image for vulnerabilities
  uses: projectbluefin/actions/bootc-build/scan-image@v1
  with:
    image: oci-archive:/tmp/scan-image.tar
```

If `upload-sarif` fails with "No SARIF file found", the scan step crashed before producing output — usually the wrong image reference was passed. Check whether `tag-images` in `Justfile` still re-applies the default tag after its alias-tag loop.

## Renovate and automation notes

- `.github/renovate.json5` is configured with `baseBranchPatterns: ["testing"]`
- `renovate-automerge.yml` searches for matching PRs with `--base testing`
- `promote-testing-to-main.yml` is the bridge from Renovate's `testing` branch to the `main` branch that feeds testing image builds
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

### Cosign certificate identity regexp

The `--certificate-identity-regexp` used in any `cosign verify` command **must match the workflow that actually calls `cosign sign`**. For images built via `projectbluefin/actions/reusable-build.yml`, the signing identity is:

```
https://github.com/projectbluefin/actions/.github/workflows/reusable-build.yml@...
```

Always use the same regexp as `sign-and-publish/action.yml`'s default — never hardcode `github.repository` (e.g. `projectbluefin/bluefin`) alone:

```yaml
# WRONG — only matches the caller repo, not the shared actions repo that signs
--certificate-identity-regexp "https://github.com/${{ github.repository }}/.github/workflows/"

# CORRECT — matches the full set of repos that can sign
--certificate-identity-regexp "https://github.com/${{ github.repository_owner }}/(bluefin|bluefin-lts|aurora|actions)/.github/workflows/"
```

Before writing or editing any `cosign verify` command, read `projectbluefin/actions/bootc-build/sign-and-publish/action.yml` to confirm the `certificate-identity-regexp` default and cosign version. The verify must be ≥ as broad as the sign step.

### Cosign installer — always use the action, never curl

Any workflow step that calls `cosign verify` must install cosign via `sigstore/cosign-installer`, **not** a raw `curl` download. Cosign v3 (installed by `sigstore/cosign-installer@v4.1.2`) uses a new signature bundle format that v2.x binaries cannot verify. If a hardcoded version string like `v2.5.0` appears in a `curl` block, the verification will silently fail for all images.

```yaml
# CORRECT — pin the same SHA used in projectbluefin/actions reusable-build
- name: Install cosign
  uses: sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6 # v4.1.2
```

Keep this SHA in sync with whatever `projectbluefin/actions` pins. Renovate tracks it.

### Known gaps

| Gap | Description |
|-----|-------------|
| Testing stream skips SBOM | Promoted `:stable`/`:latest` images lack signed SBOMs; `generate-release.yml` uses `continue-on-error` workaround — see #424 |
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
| `verify-e2e` fails: "No successful build run found for SHA" | Promotion dispatched while testing build still in-progress | Wait: `gh run watch <build-run-id> --repo projectbluefin/bluefin --exit-status` then dispatch |
| `promote-to-latest-and-stable` cosign verify fails | `--certificate-identity-regexp` too narrow — images signed by `projectbluefin/actions`, not `projectbluefin/bluefin` | Use `(bluefin\|bluefin-lts\|aurora\|actions)` regexp — see Security → Cosign certificate identity regexp |
| Renovate auto-merge finds no PR | Author filter mismatch (renovate[bot] vs app/mergeraptor) | Check jq filter in `renovate-automerge.yml` includes both |
| `generate-release.yml` fails with "No SBOM referrer found" | Testing stream skips SBOM; promoted images lack referrers | See `allow_missing_sbom=True` pattern in skill Learnings |
| Cosign sign/verify fails | Sigstore Fulcio/Rekor outage or key rotation | Check `check-cosign-key-rotation.yml` issues; retry after Sigstore recovers |
| Promotion PR shows CONFLICTING | Commit landed directly on `main` without going through `testing`, severing git merge base | Run `git merge projectbluefin/main --allow-unrelated-histories -X ours` on `testing` and push — see "Squash-merge history gap" above |
| Trivy scan crashes: "No SARIF file found" | Image reference passed to scan no longer exists — `tag-images` untags the default tag | Verify `tag-images` Justfile recipe re-applies the default tag after alias-tag loop; scan must use `oci-archive:/tmp/scan-image.tar` |

## Complete workflow inventory

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-validation.yml` | PRs to `testing`, `merge_group` | Fast validation: `just check`, `shellcheck`, `pre-commit`, e2e smoke |
| `pr-smoke.yml` | PRs touching build files | Full image build + smoke test |
| `promote-testing-to-main.yml` | Push to `testing`, daily 23:00 UTC, dispatch | Upserts the long-lived `testing` → `main` PR and enables squash auto-merge |
| `sync-main-to-testing.yml` | Push to `main` | Merges `main` → `testing` after each squash-merge promotion; prevents `BEHIND` on next promotion PR |
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
