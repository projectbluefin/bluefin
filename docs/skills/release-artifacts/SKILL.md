---
name: release-artifacts
version: "1.0"
last_updated: 2026-08-06
id: release-artifacts
one_line_purpose: Prepare, verify, and troubleshoot image release and promotion.
entry_point: docs/skills/release-artifacts/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [release, promotion, signing, verification]
description: >-
  Covers the release and testing-to-main promotion workflows, digest and tag
  verification, and signing gates. Use when running a release or diagnosing
  a failed promotion.
metadata:
  type: runbook
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

## Verify a stream tag against its gate

A stream tag (`:testing`, `:stable`) is a claim that a digest passed its gate.
Verify the claim rather than trusting the tag: resolve what the tag points at,
then confirm that digest actually passed.

```bash
skopeo inspect docker://ghcr.io/projectbluefin/bluefin:testing --format '{{.Digest}}'
gh run list --repo projectbluefin/bluefin --workflow post-testing-e2e.yml --limit 20
```

A promotion job reported as `skipped` while the stream tag still advanced means
something outside the gate is publishing it. Build-time tag computation is the
usual source: the bare stream tag can sit in the tag list that the push step
consumes, so excluding it from a conditional does not remove it from the push.
Filter the stream tag out of the list itself.

Never re-point or delete a published stream tag to "repair" this — that is
user-visible and belongs to a human.

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
- Trusting a stream tag as evidence of promotion without resolving its digest.
- A promotion job that has never succeeded, yet its stream tag keeps advancing.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The stream tag's digest was resolved and traced to a passing gate run.
- [ ] The repository default gate passes.
