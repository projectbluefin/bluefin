---
name: security
version: "1.0"
last_updated: 2026-08-06
id: security
one_line_purpose: Review supply-chain, signing, COPR, and secure-boot changes.
entry_point: docs/skills/security/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [security, supply-chain, signing, secure-boot, copr]
description: >-
  States the package-source trust boundaries, signing requirements, and
  secure-boot constraints for this image. Use when adding a package source
  or changing verification or trust behavior.
metadata:
  type: policy
  source-of-truth:
    - SECURITY.md
    - build_files/shared/copr-helpers.sh
    - .github/workflows/
---

# Security

## Use when

- Adding or reviewing a package source.
- Changing signing, verification, secure boot, or release trust behavior.

## Procedure

1. Read `SECURITY.md` and the affected source.
2. Prefer first-party or distribution repositories.
3. Treat new third-party repositories as exceptional.
4. Preserve explicit verification and isolation steps.
5. Run the focused check plus the default repository gate.

```bash
just check
pre-commit run --all-files
```

For container signatures, use the repository's existing verification recipe;
do not invent a replacement key or trust path.

## References

- [COPR isolation invariant](references/copr-isolation.md)
- [signing and verification](references/signing.md)
- [CVE-2026-33186 grpc in buildah and podman](references/cve-2026-33186-grpc-buildah.md)

## When to Use

Use for Supply-chain, signing, package-source, or secure-boot review.

## When NOT to Use

Do not use for Routine package or build work without a trust-boundary change.

## Core Process

Read the policy and source, preserve isolation and verification, run focused checks.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Disabling verification or treating isolation as optional cleanup.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
