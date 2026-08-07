---
name: packages
version: "1.1"
last_updated: "2026-08-07"
id: packages
one_line_purpose: Add, remove, or classify RPM, Flatpak, COPR, and Homebrew inputs.
entry_point: docs/skills/packages/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [packages, rpm, flatpak, copr, homebrew]
description: >-
  Provides the decision tree for where a package belongs and the files that
  declare each package source. Use when adding, removing, or relocating a
  package input.
metadata:
  type: procedure
  source-of-truth:
    - build_files/packages/base.toml
    - build_files/base/03-packages.sh
    - build_files/shared/copr-helpers.sh
    - build_files/shared/read-packages
    - system_files/shared/usr/share/flatpak/preinstall.d/
    - image-versions.yml
---

# Packages

## When to Use

- Adding, removing, or relocating an RPM, Flatpak, COPR, or Homebrew input.
- Deciding which layer a new dependency belongs in.

## When Not to Use

- Generic build validation: use [build](../build/SKILL.md).
- Release or promotion debugging: use [ci](../ci/SKILL.md).

## Decision tree

| Need | Preferred location | Declared in |
|---|---|---|
| GUI application | Flatpak | `system_files/shared/usr/share/flatpak/preinstall.d/*.preinstall`, plus the `99-flatpaks.sh` privileged setup hook |
| CLI or user tool | Homebrew | The `brew` image pinned in `image-versions.yml`; not declared per-package in this repo |
| Required system dependency | Fedora RPM | `build_files/packages/base.toml` → `[fedora]` (or `[fedora_v4X]` for a version-specific addition) |
| Multimedia replacement | negativo17 `fedora-multimedia` | `build_files/packages/base.toml` → `[multimedia_overrides]` |
| Third-party RPM | Isolated COPR | `copr_install_isolated` in `build_files/base/03-packages.sh` |
| Removal from the base image | Exclusion list | `build_files/packages/base.toml` → `[excluded]` |
| Legacy application | External user-space environment (distrobox) | Not an image input |

`build_files/packages/base.toml` is read by `build_files/shared/read-packages`,
which `03-packages.sh` invokes. Add package names there, never as an inline
shell array.

## Core Process

1. Search the repository and the `common` overlay before adding a new source.
2. Add the package to the correct `base.toml` section, or to the isolated COPR
   call if it is third-party.
3. Keep Fedora and COPR package transactions separate. `03-packages.sh`
   installs Fedora, Tailscale, and multimedia packages in one bulk transaction,
   then installs COPR packages individually through `copr_install_isolated`.
4. For images installed with `bootc install`, keep `bootupd` listed explicitly
   in `[fedora]`; do not rely on the base image to provide it transitively.
5. Validate:

```bash
just check
pre-commit run --all-files
bats tests/unit/03-packages_test.bats tests/unit/package-lib_test.bats
```

For shell changes:

```bash
bash -n build_files/base/03-packages.sh
shellcheck build_files/**/*.sh
```

## Security boundary

COPR installs must preserve the helper's enable → disable → explicit-install
sequence. See [COPR isolation](../security/references/copr-isolation.md).

## Red Flags

- Putting package data in an inline shell array instead of `base.toml`.
- Adding a COPR package to the bulk Fedora `dnf5 install` transaction.
- Adding a COPR without `copr_install_isolated`, or dropping the `copr disable`
  step.
- Assuming `flatpaks/` or `brew/` directories exist in this repository — they
  do not.
- Pinning a version without a comment linking the regression it works around.

## Verification

```bash
# Package manifest sections and their contents
grep -n '^\[' build_files/packages/base.toml

# How the manifest is consumed
grep -n 'READ_PKGS\|PKGS_TOML\|copr_install_isolated' build_files/base/03-packages.sh

# Every COPR this image enables
grep -rn 'copr_install_isolated' build_files/

# Flatpak declarations
ls system_files/shared/usr/share/flatpak/preinstall.d/

# Homebrew image pin
cat image-versions.yml
```
