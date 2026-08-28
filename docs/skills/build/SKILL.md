---
name: build
version: "1.0"
last_updated: 2026-08-06
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

## Use when

- Editing `Containerfile`, `build_files/`, `system_files/`, or image inputs.
- Running local validation or deciding whether a full build is necessary.

## Do not use when

- Debugging a workflow: use [ci](../ci/SKILL.md).
- Changing package placement: use [packages](../packages/SKILL.md).
- Reviewing trust boundaries: use [security](../security/SKILL.md).

## Procedure

1. Read the affected source and [`../../architecture.md`](../../architecture.md).
2. Run the lightest checks first:

```bash
just check
pre-commit run --all-files
```

3. For shell or hook changes, run:

```bash
bats tests/unit/
```

4. Build only when image assembly changed:

```bash
just build <image> <stream> <flavor>
just clean
```

## Hard rules

- Do not add a second orchestrator for the stage sequence; the `Containerfile`
  is the only one. Every `build_files/base/*.sh` must be invoked by it —
  `tests/unit/build_stage_reachability_test.bats` enforces this.
- Keep `build_files/base/04-install-kernel-akmods.sh` as an entrypoint wrapper;
  the orchestration logic lives in `04-install-kernel-akmods.py`.
- `/tmp` does not persist between container `RUN` instructions.
- Preserve Containerfile cache boundaries.
- Report expensive builds accurately.

## Verify

A build task is complete only when the relevant focused checks pass and any
required image validation is reported honestly.

## When to Use

Use for Build or image changes.

## When NOT to Use

Do not use for Pure workflow, package-placement, or security-policy work.

## Core Process

Read the source, run focused checks, then run the default gate.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Full builds for documentation-only changes; editing dead orchestration code.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
