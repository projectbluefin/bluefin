---
name: variants
description: Determine the correct image, stream, flavor, branch, and workflow target.
metadata:
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
