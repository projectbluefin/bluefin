# Bluefin CI reference

## Pipeline overview

Bluefin's CI is split between PR validation, image builds, post-build e2e, weekly promotion, and repo automation.

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-validation.yml` | PRs to `testing`, `merge_group` | Fast validation: `just check`, `shellcheck`, `pre-commit` |
| `build-image-testing.yml` | Push to `main`, `merge_group`, dispatch, workflow call | Builds testing images via `reusable-build.yml` |
| `post-testing-e2e.yml` | Successful `Testing Images` workflow on `main` push | Downloads the testing digest and runs smoke tests in `projectbluefin/testsuite` |
| `weekly-testing-promotion.yml` | Tuesday 06:00 UTC, manual dispatch | Verifies e2e on current `main`, promotes `main` to `latest` + `stable`, triggers downstream builds |
| `build-image-stable.yml` | Push to `stable`, dispatch, workflow call | Builds stable images and then runs `generate-release.yml` |
| `build-image-latest-main.yml` | PR/push to `latest`, `merge_group`, dispatch | Builds latest images |
| `renovate-automerge.yml` | Successful `PR Validation — testsuite` workflow | Enables squash auto-merge for matching Renovate PRs |
| `bonedigger.yml` | Issue events, issue comments, daily schedule | Runs the Bluefin 🦖 issue lifecycle bot |

## `reusable-build.yml`

This is the shared image build engine used by testing/stable/latest workflows.

- Matrix: `bluefin`
- Flavors: `main`, `nvidia-open`
- Default architecture: `x86_64`
- Runs `just check` before building
- Builds with `just build-ghcr`, then rechunks, retags, runs secureboot checks, and generates tags
- On non-PR events it pushes to GHCR, signs images with cosign, uploads SBOMs, and emits attestations
- On PR events it uploads a `.oci` artifact and prints bootc test instructions instead of pushing

## How PRs are validated

A normal Bluefin PR should target `testing`.

`pr-validation.yml` runs these steps:

1. Checkout
2. Install `just`
3. Install `shellcheck`
4. Install `pre-commit`
5. Run `just check`
6. Run `shellcheck build_files/**/*.sh`
7. Run `pre-commit run --all-files`

This workflow is intentionally fast. It validates repo health without doing a full local-style container build.

## How testing promotion works

There are two different branch roles to keep straight:

- **Contribution branch:** PRs land on `testing`
- **Image promotion branch flow in current workflows:** `main` → `latest` / `stable`

Current automation works like this:

1. A push to `main` runs `build-image-testing.yml`
2. `post-testing-e2e.yml` waits for that build, downloads `image-digest-testing-bluefin-main`, and runs the `smoke` suite from `projectbluefin/testsuite`
3. `weekly-testing-promotion.yml` locks the current `main` SHA
4. It verifies `post-testing-e2e` already passed for that exact SHA
5. It reruns broader `developer` and `vanilla-gnome` suites
6. If `main` did not advance during testing, it fast-forwards `latest` and `stable`
7. It triggers `build-image-stable.yml` on `stable` and `build-image-latest-main.yml` on `latest`

The weekly promotion workflow refuses to promote untested code.

## Renovate and automation notes

- `.github/renovate.json5` is configured with `baseBranchPatterns: ["testing"]`
- `renovate-automerge.yml` currently searches for matching PRs with `--base main`
- If Renovate PRs stop auto-merging, check that branch assumptions still match between Renovate config and the auto-merge workflow

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
| Renovate auto-merge finds no PR | Branch filter mismatch between config and workflow | Check `.github/renovate.json5` vs `renovate-automerge.yml` |

## Related files

- `.github/workflows/pr-validation.yml`
- `.github/workflows/build-image-testing.yml`
- `.github/workflows/reusable-build.yml`
- `.github/workflows/post-testing-e2e.yml`
- `.github/workflows/weekly-testing-promotion.yml`
- `.github/workflows/build-image-stable.yml`
- `.github/workflows/build-image-latest-main.yml`
- `.github/workflows/renovate-automerge.yml`
- `.github/workflows/bonedigger.yml`
