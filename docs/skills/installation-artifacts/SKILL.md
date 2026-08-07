---
name: installation-artifacts
version: "2.0"
last_updated: 2026-08-07
id: installation-artifacts
one_line_purpose: Locate the installation media that consumes a published image.
entry_point: docs/skills/installation-artifacts/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [iso, anaconda, titanoboa, installer, dakota]
description: >-
  Explains that this repository embeds the container-native ISO contract but
  builds no installation media, and where the media is actually produced. Use
  when changing Anaconda, kickstart, or live-session behavior, or chasing an ISO.
metadata:
  type: reference
  source-of-truth:
    - build_files/base/21-container-native-iso.sh
    - Containerfile
    - tests/unit/21-container-native-iso_test.bats
---

# Installation artifacts

## When to Use

- Changing Anaconda branding, partitioning defaults, kickstart post-scripts,
  Secure Boot key enrollment, or live-session tweaks.
- Someone asks you to "build the ISO" from this repository.

## Do not use when

- Promoting or verifying the image itself: use
  [release-artifacts](../release-artifacts/SKILL.md).

## This repository builds no ISO

There is no ISO workflow in `.github/workflows/` and no ISO recipe in the
`Justfile`. What this repository owns is the *contract* the ISO builder
consumes, written into the image by `build_files/base/21-container-native-iso.sh`
in a dedicated `RUN` layer of the `Containerfile` (after Stage 2, deliberately
without the `/boot` tmpfs so Titanoboa can read the committed EFI payload).

That script writes, inside the image:

| Path | Purpose |
|---|---|
| `/etc/anaconda/profile.d/bluefin.conf` | Anaconda profile, BTRFS scheme, hidden spokes |
| `/usr/share/anaconda/interactive-defaults.ks` | `ostreecontainer` payload + `%include`s |
| `/usr/share/anaconda/post-scripts/*.ks` | upgrade switch, flatpaks, Secure Boot enrollment |
| `/usr/lib/bootc-image-builder/iso.yaml` | Titanoboa GRUB entries, label `titanoboa_boot` |
| `/usr/lib/bluefin/livesys-session-extra` | live-only GNOME and unit overrides |
| `/boot/efi/EFI/` | EFI payload copied from `/usr/lib/efi/*/*/EFI` |

Media assembly happens downstream. `projectbluefin/dakota` is the BuildStream
buildstream for Bluefin and owns `build.yml` / `publish.yml`; consult that
repository, not this one, for media build and publish behavior.

## The `:stable` pin

`21-container-native-iso.sh` reads `image-ref` from
`/usr/share/ublue-os/image-info.json` and then hardcodes
`INSTALL_IMAGE="${IMAGE_REF}:stable"`. Every ISO built from any stream therefore
installs and `bootc switch`es to `:stable`. This is intentional, not a bug — do
not "fix" it to follow the build stream without a human decision.

## Procedure

1. Change the script, not the generated files; they exist only inside the image.
2. Extend `tests/unit/21-container-native-iso_test.bats` in the same change.
   The script honours `FAKE_ROOT` and `BRANDING_DIR` so it is testable without
   a container.
3. Run the unit suite and the repository gates.
4. To verify end to end, build the image and inspect the written paths rather
   than trusting the script text.

```bash
bats tests/unit/21-container-native-iso_test.bats
just check && pre-commit run --all-files
```

Never overwrite a known-good published artifact to force a broken rebuild
through.

## Red Flags

- Looking for an ISO workflow or `just iso` recipe in this repository.
- Editing a generated Anaconda or kickstart file instead of the script.
- Changing the `:stable` install pin without a human decision.
- Promoting media without first verifying the source image digest.

## Verification

- [ ] `grep -rniE '\biso\b' .github/workflows/ Justfile` returns nothing —
      this repository still builds no media.
- [ ] `grep -n '21-container-native-iso' Containerfile` shows the script is
      still invoked.
- [ ] `bats tests/unit/21-container-native-iso_test.bats` passes.
