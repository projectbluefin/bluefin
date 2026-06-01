# Bluefin build reference

## Build model

Bluefin is a Containerfile-driven rpm-ostree/bootc image build, not a BuildStream repo.

- `Containerfile` is the top-level build definition
- Multi-stage flow: `common` / `brew` inputs → `ctx` → `base`
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
| `build_files/shared/` | Shared helpers such as `build.sh` and `copr-helpers.sh` |
| `system_files/` | Files copied verbatim into the image |
| `flatpaks/` | Flatpak lists for the image |
| `brew/` | Homebrew Brewfiles |
| `just/` | Additional just recipes |
| `.github/workflows/` | CI/CD pipeline definitions |
| `docs/` | Agent reference docs |

## Dev loop

```bash
just check
pre-commit run --all-files

just fix
just check

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
| `bluefin` | `gts`, `stable`, `latest`, `beta` | `main`, `nvidia-open` |

The current branch automation also carries a `testing` stream in local/CI recipes; use the release and CI docs for branch-specific pipeline behavior.

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
