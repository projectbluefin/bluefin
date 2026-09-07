---
name: installation-artifacts
version: "1.0"
last_updated: 2026-08-06
id: installation-artifacts
one_line_purpose: Build and promote installation artifacts that consume the image.
entry_point: docs/skills/installation-artifacts/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [artifacts, iso, promotion, release]
description: >-
  Covers dispatching artifact workflows, confirming the source image digest,
  and promoting a verified artifact. Use when building or promoting an ISO
  or other installation artifact derived from a published image.
metadata:
  type: runbook
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

## Container-native ISO contract

`build_files/base/21-container-native-iso.sh` embeds the contract the ISO
builder consumes, but only the parts that belong in a bootc image: the Anaconda
profile and post-scripts, the livesys hooks, and
`/usr/lib/bootc-image-builder/iso.yaml`.

The shim and grub2 EFI payload stays where its RPMs put it,
`/usr/lib/efi/*/*/EFI`. The contract asks for it in `/boot/efi/EFI/$VENDOR`, and
the ISO builder stages it there in its own throwaway layer, exactly as the
[reference implementations](https://github.com/ondrejbudai/bootc-isos/blob/main/bluefin-lts/src/build.sh)
do:

```bash
mkdir -p /boot/efi && cp -a /usr/lib/efi/*/*/EFI /boot/efi/
```

Do not move that copy back into the image. `/boot` must ship empty or every
derived image fails `bootc container lint --fatal-warnings`. See
[#1208](https://github.com/projectbluefin/bluefin/issues/1208).

## When to Use

Use for Installation media or downstream image artifacts.

## When NOT to Use

Do not use for Normal image build or release metadata only.

## Core Process

Verify source digest, read artifact workflow, use explicit safe inputs.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Promoting an artifact without verifying its source image.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
