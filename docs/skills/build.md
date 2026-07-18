---
name: build
description: Build, validate, and test Bluefin image changes. Use when editing Containerfile stages, build scripts, image contents, or local validation.
metadata:
  context7-sources:
    - /osbuild/bootc-image-builder
    - /rpm-software-management/dnf5
    - /websites/podman_io_en
---

# Build, Validate, and PR Workflow

## When to use

- Editing this repo and preparing a commit or PR
- Running local validation before pushing
- Building images locally to verify image-layer changes
- Checking which branch or merge strategy is allowed

## When NOT to use

- Package-only decisions → [packages.md](packages.md)
- GitHub Actions failures → [ci.md](ci.md)
- Bluefin LTS repo work → `projectbluefin/bluefin-lts` repo
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

## Core Process

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
| nvidia build fails: `dracut[E]: FAILED … -D /var/tmp/dracut.*/initramfs` | `04-install-kernel-akmods.sh` calls `dracut` without `--tmpdir /boot`; `/var/tmp` and `/boot` are separate tmpfs mounts in a container `RUN` layer — `rename(2)` across devices fails with EXDEV | add `--tmpdir /boot` to the explicit `/usr/bin/dracut` call in `04-install-kernel-akmods.sh`. See PR #586. |

## Build pipeline and shared actions

### Pipeline flow

```text
PR validation (just check + pre-commit + shellcheck)
  → testing build (Containerfile → GHCR :testing)
  → e2e smoke test (boot + package assertions)
  → daily automated promotion (:testing digest → :stable)
  → release generation
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

### Stable container-native ISO contract

Stable ISO support is embedded in the image by
`build_files/base/21-container-native-iso.sh`. Keep it in a separate final-stage
`RUN` without the `/boot` tmpfs: Titanoboa reads the committed
`/boot/efi/EFI` payload and `/usr/lib/bootc-image-builder/iso.yaml` directly
from the source image. The final bootc lint skips only `nonempty-boot`, because
that content is intentional for the ISO contract; live-session state remains
packaged under `/usr` and is materialized under `/var` through tmpfiles.

Current Titanoboa copies the source root filesystem into the live squashfs but
does not seed `/var/lib/containers/storage`. Anaconda therefore uses
`ostreecontainer --transport=registry`; `containers-storage` is only valid if
the ISO builder explicitly embeds a payload image. The installer always targets
the promotion-safe `:stable` image reference, even when the source image was
built as `:testing` before release promotion.

The Stage 1 initramfs includes the live ISO dracut modules and writes
`.bluefin-initramfs-done`. Stage 2 preserves the existing marker/cache contract;
the ISO finalization layer must not regenerate dracut unconditionally.

Use `livesys-scripts` extension hooks for live-only mutations. Static service
disables or GNOME schema overrides in the source image would also affect normal
installed Bluefin systems.

## Lessons learned

### `yelp` is deprecated — do not install it

`yelp` (the GNOME help viewer) is deprecated upstream. Do not add it to the package list as a fix for `help://` URI failures (e.g. the Nautilus Templates tooltip). The correct approach is to override or suppress the `help://` URI handler at the GNOME/desktop level, not to install a deprecated viewer.

## Common Rationalizations

- "A unit test is enough for an image-content change."
  Run the package transaction or image build when practical; unit tests cannot
  prove RPM dependency resolution.
- "The finalization layer can keep the `/boot` tmpfs."
  Not for container-native ISO assets: Titanoboa must read committed EFI files.
- "Live-session settings can be written directly into the image."
  Static settings also affect installed Bluefin; use livesys conditional hooks.

## Red Flags

- Writing persistent ISO assets while `/boot` is mounted as tmpfs.
- Using `containers-storage` without an explicitly embedded installer payload.
- Disabling normal Bluefin services in the source image for live-session needs.
- Updating the unused `build_files/shared/build.sh` orchestrator.

## Verification

- [ ] Focused BATS coverage passed after an observed RED failure.
- [ ] New RPM names resolve in the target Fedora repositories.
- [ ] `just check` passed.
- [ ] `pre-commit run --all-files` passed.
- [ ] Full image build or package-transaction validation is reported accurately.

## Sources

- Context7 `/osbuild/bootc-image-builder` — ISO configuration reference.
- Context7 `/rpm-software-management/dnf5` — package installation and repoquery.
- Context7 `/websites/podman_io_en` — ephemeral container execution.
- `ublue-os/titanoboa` container-native contract and builder implementation:
  <https://github.com/ublue-os/titanoboa/tree/5c457c3d0518bd17e754be0fd98a60d29d26abb4>
