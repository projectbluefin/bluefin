---
name: build
version: "1.1"
last_updated: "2026-08-07"
id: build
one_line_purpose: Build, validate, and test image changes locally before pushing.
entry_point: docs/skills/build/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [build, containerfile, justfile, validation]
description: >-
  Covers Containerfile stages, build_files layering, local image builds, and
  which validation gate to run for a given change. Use when editing image
  inputs or deciding whether a full build is required.
metadata:
  type: procedure
  source-of-truth:
    - Containerfile
    - Justfile
    - build_files/
    - tests/
---

# Build

## When to Use

- Editing `Containerfile`, `build_files/`, `system_files/`, or image inputs.
- Running local validation or deciding whether a full build is necessary.

## When Not to Use

- Debugging a workflow: use [ci](../ci/SKILL.md).
- Changing package placement: use [packages](../packages/SKILL.md).
- Reviewing trust boundaries: use [security](../security/SKILL.md).
- Choosing an image/tag/flavor target: use [variants](../variants/SKILL.md).

## Core Process

1. Read the affected source and [`../../architecture.md`](../../architecture.md).
2. Run the lightest checks first. `just check` only verifies `Justfile`
   formatting; `pre-commit` runs shellcheck, actionlint, and this repo's
   documentation validator (`.pre-commit-config.yaml`).

```bash
just check
pre-commit run --all-files
```

3. For shell or hook changes, run the Bats suite (`just test-unit` wraps this
   and fails early when `bats` is missing):

```bash
bats tests/unit/
python3 -m unittest discover -s tests -p 'test_*.py'
```

4. Build only when image assembly changed. The recipe signature is
   `build $image $tag $flavor` — the second argument is a **tag**, not a
   stream name, and `just validate` rejects anything outside the `Justfile`
   maps (see [variants](../variants/SKILL.md)):

```bash
just build bluefin testing main
just clean
```

A local build resolves and cosign-verifies the `silverblue` base digest before
building. `SKIP_BASE_VERIFY=1` is honoured only when `CI` is not `true`.

## Containerfile layering

`Containerfile` splits the build so unrelated edits do not invalidate the
expensive package layer:

| Stage | Purpose |
|---|---|
| `ctx-build` | `scratch` context holding only `build_files/` + `image-versions.yml` |
| `ctx` | `scratch` context with `system_files/`, `build_files/`, and the `common` and `brew` overlays |
| `base-common` | Stage 1 — `03-packages.sh`, `04-install-kernel-akmods.sh`, `05-override-install.sh`, mounted from `ctx-build` |
| `extension-builder` | Builds GNOME Shell extensions |
| `base` | Stage 2 — `system_files` overlay, `00-image-info.sh`, cleanup, initramfs, repo validation, `20-tests.sh`, then the container-native ISO layer |

Buildah folds the mounted stage's image ID into the `RUN` cache key, which is
why the package stage mounts `ctx-build` and not `ctx`. `BUILD_FILES_SHA` is a
second, explicit cache key over `build_files/`.

## Red Flags

- Running a full image build for a documentation-only change.
- Editing `build_files/shared/build.sh` — nothing references it.
- Adding orchestration to `build_files/base/04-install-kernel-akmods.sh`; it is
  a wrapper that `exec`s `04-install-kernel-akmods.py`.
- Widening the Stage 1 bind mount to `ctx`, which destroys the cache split.
- Assuming `/tmp` persists between container `RUN` instructions.
- Reporting a build as verified when only `just check` was run.

## Verification

```bash
# Recipe signature and argument names
grep -n '^build \$image' Justfile

# Confirm build_files/shared/build.sh is unreferenced
git grep -n 'shared/build.sh' -- . ':!docs'

# Confirm the akmods wrapper only execs the Python orchestrator
cat build_files/base/04-install-kernel-akmods.sh

# Confirm the Stage 1 / Stage 2 mount split
grep -n 'from=ctx-build\|from=ctx,' Containerfile

# Default gate
just check && pre-commit run --all-files
```
