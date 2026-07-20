---
name: build
description: Build, validate, and test image changes. Use for Containerfile, build scripts, image contents, or local validation.
metadata:
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

- Do not update the unused `build_files/shared/build.sh`.
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
