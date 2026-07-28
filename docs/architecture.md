# Architecture

## Build model

This is a Containerfile-driven rpm-ostree/bootc image repository, not a
BuildStream repository.

- `Containerfile` defines the image stages.
- `Justfile` is the local operator interface.
- `build_files/base/` contains ordered image scripts.
- `build_files/shared/` contains reusable build helpers.
- `system_files/` contains files copied into the image.
- `tests/unit/` contains Bats coverage.
- `.github/workflows/` contains CI and release callers.

`build_files/shared/build.sh` is unused legacy code. Do not update or reference
it.

## Cache boundaries

The Containerfile separates package installation from final filesystem overlay:

- Stage 1 installs packages and kernel-related inputs.
- Stage 2 overlays system files and performs finalization and tests.

Changes to `system_files/` should not invalidate Stage 1 package layers. Files
that must survive separate container `RUN` instructions belong on the committed
filesystem, not in `/tmp`.

## Local loop

```bash
just check
pre-commit run --all-files
bats tests/unit/
```

Run `just build` only for changes that affect image assembly, then use
`just clean` to reclaim build artifacts.

## Source-of-truth rule

When this document disagrees with `Containerfile`, `Justfile`, build scripts,
tests, or workflows, the source wins. Update this document in the same change
when a stable architectural invariant changes.
