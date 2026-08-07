---
name: variants
version: "1.0"
last_updated: 2026-08-06
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
    - image-versions.yml
    - .github/workflows/
---

# Variants

## Procedure

1. Read the image mapping in `Justfile`.
2. Read the relevant build workflow matrix.
3. Confirm the published tag from the workflow, not memory.
4. Use the exact image reference in commands and reports.

Do not infer that a branch, stream, or flavor is published merely because a
name appears in documentation. Update this skill when the matrix changes.

## Verify

```bash
git grep -n 'image_name\|stream\|flavor' Justfile image-versions.yml .github/workflows
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
