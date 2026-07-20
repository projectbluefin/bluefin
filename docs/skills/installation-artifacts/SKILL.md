---
name: installation-artifacts
description: Build or promote installation artifacts that consume the image.
metadata:
  source-of-truth:
    - .github/workflows/
    - docs/release.md
---

# Installation artifacts

## Procedure

1. Confirm the source image digest and published tag.
2. Read the artifact workflow before dispatching it.
3. Use the workflow's explicit safe variant and promotion inputs.
4. Verify the artifact exists before promoting it.
5. Report failed upstream image publication separately from artifact failure.

Never overwrite a known-good artifact to force a broken rebuild through.
