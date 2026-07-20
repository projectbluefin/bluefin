---
name: packages
description: Add, remove, or classify RPM, Flatpak, COPR, and Homebrew inputs.
metadata:
  source-of-truth:
    - build_files/packages/
    - build_files/base/03-packages.sh
    - build_files/shared/copr-helpers.sh
    - flatpaks/
    - brew/
---

# Packages

## Decision tree

| Need | Preferred location |
|---|---|
| GUI application | Flatpak |
| CLI or user tool | Homebrew |
| Required system dependency | Fedora RPM |
| Third-party RPM | Isolated COPR |
| Legacy application | External user-space environment |

## Procedure

1. Search the repository and shared inputs before adding a new source.
2. Put base package data in the package manifest, not an inline shell array.
3. Keep Fedora and COPR package transactions separate.
4. Run:

```bash
just check
pre-commit run --all-files
```

For shell changes:

```bash
bash -n build_files/base/03-packages.sh
shellcheck build_files/**/*.sh
```

## Security boundary

COPR installs must preserve the helper's enable → disable → explicit install
sequence. See [COPR isolation](../security/references/copr-isolation.md).

## When to Use

Use for RPM, Flatpak, COPR, or Homebrew input changes.

## When NOT to Use

Do not use for Generic build validation or release debugging.

## Core Process

Classify the input, edit its source manifest, validate resolution and policy.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Putting package data in the wrong layer or mixing trusted and third-party sources.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
