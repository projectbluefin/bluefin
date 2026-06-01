# Package Management

## When to use

- Adding, removing, or updating RPM packages in the image
- Handling COPR packages safely
- Figuring out whether a change belongs in RPM, Flatpak, or Homebrew
- Touching DX-only package sets

## When NOT to use

- General build/PR workflow → [build.md](build.md)
- COPR security policy details → [security.md](security.md)
- CI breakage after a package change → [ci.md](ci.md)

## Decision tree

| Need | Preferred path |
|---|---|
| GUI app for end users | Flatpak first |
| CLI or dev tool for users | Homebrew |
| System dependency required in the image | Fedora RPM |
| Third-party RPM not in Fedora | COPR, isolated |
| Legacy app that does not fit the image model | distrobox, not image layering |

## Package locations

| Type | Location | Notes |
|---|---|---|
| Base RPMs | `build_files/base/03-packages.sh` | Main `FEDORA_PACKAGES` list |
| DX RPMs | `build_files/dx/00-dx.sh` | Developer-only packages |
| COPR helper | `build_files/shared/copr-helpers.sh` | Use `copr_install_isolated()` |
| Flatpak setup hooks | `system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh` | This repo currently carries setup, not the full app list |
| Brew-triggered user setup | `system_files/shared/usr/share/ublue-os/user-setup.hooks.d/` | Example: Framework laptop casks |

## RPM changes

Edit the correct array, then validate syntax:
```bash
bash -n build_files/base/03-packages.sh
bash -n build_files/dx/00-dx.sh
just check && pre-commit run --all-files
```

Base image packages belong in:
```bash
build_files/base/03-packages.sh
```

DX-only packages belong in:
```bash
build_files/dx/00-dx.sh
```

## COPR changes

**Never mix Fedora and COPR packages in one array.**

Correct pattern:
```bash
# Fedora packages
FEDORA_PACKAGES=(
  fastfetch
  htop
)

# COPR packages are installed separately
copr_install_isolated \
  "ublue-os/packages" \
  "uupd" \
  "oversteer-udev"
```

Validation:
```bash
bash -n build_files/base/03-packages.sh
shellcheck build_files/**/*.sh
```

## Flatpak changes

Bluefin is Flatpak-first for GUI apps.
If a requested GUI app can be shipped as a Flatpak, prefer that over layering RPMs.

Check whether the app is actually managed in this repo or in a shared repo before editing.
Search first:
```bash
git grep -n 'flatpak' -- .
```

## Homebrew changes

Use Homebrew for CLI tools and user-space developer tooling.
Validate the cask/formula exists before referencing it.

Example container check:
```bash
podman run --rm docker.io/homebrew/brew:latest bash -c "
  brew tap ublue-os/tap 2>&1 | tail -3 && \
  brew info --cask 'ublue-os/tap/CASK_NAME' 2>&1
"
```

For formulas:
```bash
podman run --rm docker.io/homebrew/brew:latest bash -c "
  brew tap ublue-os/tap 2>&1 | tail -3 && \
  brew info --formula 'FORMULA_NAME' 2>&1
"
```

## Non-obvious patterns

- GUI apps: prefer Flatpak, not layered RPMs
- VS Code for development should be installed via Homebrew, not Flatpak
- If a package is hardware- or user-setup-specific, it may belong in a setup hook instead of the base image
- This repo may reference `flatpaks/**` in workflows even when the content is maintained elsewhere; search before assuming the path exists

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `bash -n` fails | shell syntax error | fix script before any CI retry |
| package not found | wrong repo/source | verify Fedora/COPR/Homebrew source first |
| Brew validation says no formula/cask | wrong tap name or upstream not merged | fix the name or wait for tap merge |
| package should be GUI-facing but was added as RPM | wrong packaging model | move it to Flatpak or Homebrew |

## Lessons learned

<!-- Add reusable package patterns here -->
