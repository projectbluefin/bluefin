---
name: variants
version: "1.0"
last_updated: 2026-08-30
id: variants
one_line_purpose: Determine the correct image, stream, flavor, branch, and target.
entry_point: docs/skills/variants/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [variants, images, streams, tags]
description: >-
  Maps image names, streams, flavors, and branches to their published tags
  and build workflows. Use when choosing an image reference for a command,
  report, or workflow dispatch.
metadata:
  type: reference
  source-of-truth:
    - Justfile
---

# Variants

`Justfile` is the single source of the variant matrix. The `images` and
`flavors` maps declare the axes; the `image_name` recipe derives a published
image name from an (image, flavor) pair — the bare image name for the `main`
flavor, `<image>-<flavor>` otherwise. `image-versions.yml` pins the *upstream*
images the build consumes; it does not declare what this repo publishes.

Every workflow that names a published variant is a restatement of that
derivation, not an independent source:

| Site | Restates |
|---|---|
| `.github/workflows/build-image-testing.yml` | default `image_flavors` list |
| `.github/workflows/execute-release.yml` | `variants` matrix, digest loop, release-notes table |
| `.github/workflows/promote-testing-to-main.yml` | `variants` matrix |
| `.github/workflows/vulnerability-scan.yml` | `image_matrix` |

`tests/unit/image_variant_matrix_test.bats` holds all of them to the Justfile
derivation, so a variant that is built but not scanned, or promoted but not
released, fails the unit-test gate instead of shipping.

## Procedure

1. Read the `images` and `flavors` maps in `Justfile`.
2. Derive the published name with the `image_name` rule above.
3. Confirm the published tag from the workflow, not memory.
4. Use the exact image reference in commands and reports.

Do not infer that a branch, stream, or flavor is published merely because a
name appears in documentation. Adding or removing a variant means editing the
`Justfile` maps *and* every restatement site above; the gate lists whichever
ones you missed.

## Verify

```bash
bats tests/unit/image_variant_matrix_test.bats
git grep -n 'image_name\|stream\|flavor' Justfile .github/workflows
just check
```

## When to Use

Use for Image, stream, flavor, or target selection.

## When NOT to Use

Do not use for Implementation changes unrelated to image targeting.

## Core Process

Read the Justfile and workflow matrix, then use the exact source-derived target.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Inferring published tags from prose.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
