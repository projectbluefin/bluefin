---
name: security
description: Review image supply-chain, signing, COPR, and secure-boot changes.
metadata:
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
