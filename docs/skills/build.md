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
| `latest` | promoted latest stream | `.github/workflows/build-image-latest-main.yml` |
| `stable` | promoted stable stream | `.github/workflows/build-image-stable.yml` |

If CI did not start on a PR, confirm the PR targets `testing`.

## Common commands

Check local status before pushing:
```bash
git --no-pager status --short
git --no-pager diff --stat
```

Sync `testing` from `main` when needed:
```bash
git checkout testing
git merge origin/main --no-edit
git push origin testing
```

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

## Lessons learned

<!-- Add reusable build/PR patterns here -->
