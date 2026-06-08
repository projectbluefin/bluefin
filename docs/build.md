# Bluefin build reference

## Git hook setup

After cloning, install the pre-push guard that blocks accidental `git push origin`:

```bash
bash .github/scripts/install-hooks.sh
```

This installs a `pre-push` hook that blocks `git push origin` and reminds you to use `git push projectbluefin <branch>`.

## Build model

Bluefin is a Containerfile-driven rpm-ostree/bootc image build, not a BuildStream repo.

- `Containerfile` is the top-level build definition
- Multi-stage flow: `common` / `brew` inputs → `ctx` → `base-common` → `extension-builder` → `base`
- `build_files/shared/build.sh` orchestrates the numbered scripts in `build_files/base/`
- `Justfile` is the operator interface for validation, local builds, tagging, and helper commands

## Requirements

| Tool | Why |
|---|---|
| `just` | Primary automation entry point (`just check`, `just fix`, `just build`) |
| `podman` / `buildah` | Local image builds and inspection |
| `jq` + `yq` | Used by `Justfile` during image/version resolution |
| `skopeo` | Inspect and verify remote container metadata |
| `cosign` | Signature verification in the build flow |
| `pre-commit` | Required validation before committing |
| Free disk: ~25 GB | Full container builds are expensive |

## Repo layout

| Path | Purpose |
|---|---|
| `Containerfile` | Multi-stage image build (`base`) |
| `Justfile` | Build, validation, tagging, cleanup helpers |
| `build_files/base/` | Base image scripts, run in numeric order |
| `build_files/shared/` | Shared helpers such as `build.sh`, `copr-helpers.sh`, and `package-lib.sh` |
| `tests/unit/` | Bats unit tests for shared shell libraries (run with `just test-unit` or `bats tests/unit/`) |
| `system_files/` | Files copied verbatim into the image |
| `flatpaks/` | Flatpak lists for the image |
| `brew/` | Homebrew Brewfiles |
| `just/` | Additional just recipes |
| `.github/workflows/` | CI/CD pipeline definitions |
| `docs/` | Agent reference docs |

## Containerfile cache stages

The `Containerfile` intentionally splits the image build into two cache boundaries:

- **Stage 1 — package installs only**: runs `build_files/base/03-packages.sh`, `04-install-kernel-akmods.sh`, and `05-override-install.sh` with only `build_files/` mounted into the build context. This keeps package-layer cache hits intact when a change only touches `system_files/`.
- **Stage 2 — system_files overlay and cleanup**: overlays `system_files/`, then runs `build_files/base/00-image-info.sh`, `build_files/shared/build-gnome-extensions.sh`, `build_files/base/17-cleanup.sh`, `build_files/base/19-initramfs.sh`, `build_files/shared/validate-repos.sh`, `build_files/shared/clean-stage.sh`, and `build_files/base/20-tests.sh`.

`ARG SHA_HEAD_SHORT` and `ARG VERSION` are declared between these two stages on purpose. If they move before Stage 1, every commit changes the Stage 1 cache key and forces package-install rebuilds even when only metadata changed.

## Dev loop

```bash
just check
pre-commit run --all-files

just fix
just check

# Run unit tests for shared shell libraries:
just test-unit
# or equivalently:
bats tests/unit/

# Only when testing container/image changes:
just build bluefin latest main
just clean
```

### Rules of thumb

- Run `just check` first; it validates Justfile syntax across the repo
- Run `just fix` when formatting `Justfile` or `*.just` files
- Run `pre-commit run --all-files` before every commit
- **Do not run full builds unless you are testing container changes**
- Expect `just build` to take roughly 30–90 minutes and about 25 GB of disk on a cold run
- Use `just clean` to reclaim build artifacts after local image testing

## Image matrix

| Image | Streams | Flavors |
|---|---|---|
| `bluefin` | `testing`, `stable` | `main`, `nvidia` |

`:testing` is built daily from `main`. `:stable` is promoted weekly from `:testing` via `weekly-testing-promotion.yml` after e2e passes.

## Package locations

| Change type | Where to edit |
|---|---|
| Base RPMs and system package logic | `build_files/base/` |
| Shared shell helpers / COPR isolation | `build_files/shared/` |
| Files copied into the image | `system_files/` |
| Flatpak manifests | `flatpaks/` |
| Homebrew package sets | `brew/` |

## What not to do

- Do not treat this like a mutable `dnf install` workflow
- Do not run full builds for doc-only, label-only, or pure workflow edits
- Do not change unrelated stages in `Containerfile`
- Do not bypass `just check` and `pre-commit run --all-files`
