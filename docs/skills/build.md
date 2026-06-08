# Build, Validate, and PR Workflow

## When to use

- Editing this repo and preparing a commit or PR
- Running local validation before pushing
- Building images locally to verify image-layer changes
- Checking which branch or merge strategy is allowed

## When NOT to use

- Package-only decisions → [packages.md](packages.md)
- GitHub Actions failures → [ci.md](ci.md)
- Bluefin LTS repo work → [lts.md](lts.md)
- ISO builds/promotions → [iso.md](iso.md)

## Hard rules

- **All PRs target `testing`. Never `main`.**
- **Squash merge only** for `projectbluefin/bluefin` PRs.
- **Run before every commit:**
  ```bash
  just check && pre-commit run --all-files
  ```
- **Every AI-authored commit must include:**
  ```text
  Assisted-by: <Model> via <Tool>
  ```

## Default contributor loop

```bash
git checkout -b fix/my-change
just check && pre-commit run --all-files
```

If validation fails:
```bash
just fix
just check && pre-commit run --all-files
```

Open the PR directly against `testing`:
```bash
gh pr create \
  --repo projectbluefin/bluefin \
  --base testing \
  --title "fix(scope): summary" \
  --body "## Summary
- ...

## Test plan
- just check
- pre-commit run --all-files"
```

## When to build locally

Only build locally when you changed image contents, build scripts, or container logic.
Avoid full image builds for docs-only or workflow-only changes.

```bash
just build bluefin latest main
just clean
```

## Branch and workflow map

| Branch | Purpose | Key workflow |
|---|---|---|
| `testing` | PR target | `.github/workflows/pr-validation.yml` |
| `main` | testing image source | `.github/workflows/build-image-testing.yml` |

If CI did not start on a PR, confirm the PR targets `testing`.

## Common commands

Check local status before pushing:
```bash
git --no-pager status --short
git --no-pager diff --stat
```

**Branch sync is automated.** `sync-main-to-testing.yml` fires on every push to `main` and merges `main` → `testing`. No manual sync needed in normal operation.

## Non-obvious patterns

### Justfile changes

Bluefin tracks Aurora patterns closely. Before changing a Just recipe, compare against Aurora first:
```bash
curl -s https://raw.githubusercontent.com/ublue-os/aurora/main/Justfile | grep -A 20 'recipe-name'
```

### Image builds are expensive

- Full local builds are slow and disk-heavy
- Use `just clean` before retrying after space issues
- Do not use local full builds as your default validation step

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `pre-commit` fails | format/lint issue | run `just fix`, then rerun validation |
| PR has no validation run | wrong base branch | retarget PR to `testing` |
| build fails with low disk space | stale build artifacts | run `just clean` |
| workflow shows `startup_failure` with no jobs | unsupported org-only permission scope on the runner/fork | compare permissions block with a working upstream workflow |

## Build pipeline and shared actions

### Pipeline flow

```text
PR validation (just check + pre-commit + shellcheck)
  → testing build (Containerfile → GHCR :testing)
  → e2e smoke test (boot + package assertions)
  → weekly promotion (fast-forward latest/stable)
  → stable build + release generation
```

### Justfile vs GitHub Actions

| Scope | Tool | Why |
|---|---|---|
| Local validation | `just check`, `just fix` | Fast, no network needed |
| Image build | `just build` locally, centralized `projectbluefin/actions` workflow in CI | Same Containerfile, different runners |
| Promotion/signing | GitHub Actions only | Requires OIDC identity, registry access |

### Key shared actions (projectbluefin/actions)

Bluefin's CI delegates to composite actions and a reusable workflow in [`projectbluefin/actions`](https://github.com/projectbluefin/actions). The internal `reusable-build.yml` has been deleted — callers now use:

```yaml
uses: projectbluefin/actions/.github/workflows/reusable-build.yml@<SHA>
```

| Action | Build phase |
|---|---|
| `bootc-build/setup-runner` | Runner preparation (podman, cgroups) |
| `bootc-build/dnf-cache` | Package caching before build |
| `bootc-build/preflight` | Pre-build validation |
| `bootc-build/rechunk` | Post-build rpm-ostree rechunking |
| `bootc-build/push-image` | Registry push with retry |
| `bootc-build/sign-and-publish` | Signing + SBOM attach |

## Containerfile split-RUN architecture

The Containerfile uses two separate `RUN` commands:

- **Stage 1:** Package installs — `03-packages.sh`, `04-install-kernel-akmods.sh`, `05-override-install.sh`. Cache key: `build_files/`.
- **Stage 2:** Overlay + finalization — `00-image-info.sh`, `build-gnome-extensions.sh`, `19-initramfs.sh`, `validate-repos.sh`, `clean-stage.sh`, `20-tests.sh`. Cache key: `system_files/` + `build_files/shared/`.

### tmpfs does not persist between RUN commands

Each `RUN` gets its own mount namespace. Files written to `/tmp` in Stage 1 are gone in Stage 2. Sentinel files (e.g. `/tmp/.initramfs-needed`) placed by kernel install scripts in Stage 1 will never be readable by `19-initramfs.sh` in Stage 2.

### Cache invalidation

| Change type | Stage 1 | Stage 2 |
|---|---|---|
| `build_files/base/*.sh` | **bust** | bust |
| `build_files/shared/*.sh` | hit | **bust** |
| `system_files/` | hit | **bust** |
| `image-versions.yml` | **bust** | bust |

A `system_files`-only change hits Stage 1 cache and skips the full package install (~20–80 min saved).

## Lessons learned

### `yelp` is deprecated — do not install it

`yelp` (the GNOME help viewer) is deprecated upstream. Do not add it to the package list as a fix for `help://` URI failures (e.g. the Nautilus Templates tooltip). The correct approach is to override or suppress the `help://` URI handler at the GNOME/desktop level, not to install a deprecated viewer.
