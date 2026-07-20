---
name: release-artifacts
description: Prepare, verify, or troubleshoot image release and promotion artifacts.
metadata:
  source-of-truth:
    - .github/workflows/execute-release.yml
    - .github/workflows/promote-testing-to-main.yml
    - docs/release.md
---

# Release artifacts

## Procedure

1. Read the affected release workflow and reusable workflow inputs.
2. Verify the exact image digest, tag, artifact name, and trigger.
3. Confirm signing and end-to-end gates completed.
4. Never bypass a failed trust or verification gate.
5. Report the run ID and exact verification commands.

```bash
gh run list --repo projectbluefin/bluefin --limit 20
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
gh run watch RUN_ID --repo projectbluefin/bluefin --exit-status
```

## Red flags

- Re-pulling a large image during release only to generate metadata.
- Assuming a tag is updated before its promotion workflow completes.
- Re-triggering an existing release without checking idempotency.
- Describing release behavior without reading the current workflow.

## When to Use

Use for Release, promotion, digest, SBOM, or artifact work.

## When NOT to Use

Do not use for Local build-only changes.

## Core Process

Read the workflow, verify the exact digest and artifact, then inspect the run.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Guessing tags or bypassing a failed release gate.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
