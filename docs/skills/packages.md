# Package Management

## When to use

- Adding, removing, or updating RPM packages in the image
- Handling COPR packages safely
- Figuring out whether a change belongs in RPM, Flatpak, or Homebrew

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
| Base RPMs | `build_files/packages/base.toml` | TOML manifest; sections: `[fedora]`, `[fedora_v42/43/44]`, `[multimedia_overrides]`, `[excluded]` |
| COPR helper | `build_files/shared/copr-helpers.sh` | Use `copr_install_isolated()` |
| Flatpak setup hooks | `system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh` | This repo currently carries setup, not the full app list |
| Brew-triggered user setup | `system_files/shared/usr/share/ublue-os/user-setup.hooks.d/` | Example: Framework laptop casks |

## RPM changes

Base image packages live in `build_files/packages/base.toml`, not inline in the shell script.
Edit the relevant TOML section, then validate:

```bash
# Verify the manifest parses cleanly
python3 build_files/shared/read-packages build_files/packages/base.toml fedora | head
just check && pre-commit run --all-files
```

Section guide:

| Section | What goes here |
|---|---|
| `[fedora]` | Base packages for all supported Fedora versions |
| `[fedora_v42]` / `[fedora_v43]` / `[fedora_v44]` | Version-specific additions |
| `[multimedia_overrides]` | mesa/VA-API packages synced from fedora-multimedia (pinned with versionlock) |
| `[excluded]` | Packages removed from the base image after install |

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

- **Package arrays belong in TOML, not shell.** `build_files/packages/base.toml` is the data; `build_files/base/03-packages.sh` is the logic. Adding a package = editing the TOML. Never add inline bash arrays to the shell script.
- **`read-packages` helper uses `tomllib` (Python 3.11+ stdlib).** No new dependencies needed in the build container. Called as `python3 /ctx/build_files/shared/read-packages <toml> <section>` and consumed with `readarray`.
- **COPR packages stay isolated in the shell script.** The TOML only covers Fedora/multimedia repo packages. COPR installs stay in `03-packages.sh` via `copr_install_isolated()` — this is a security boundary, not an oversight.
