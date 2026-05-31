# Security Model

## When to use

- Adding or reviewing COPR-backed packages
- Verifying signed container inputs
- Running secureboot checks
- Documenting trusted vs untrusted package sources

## When NOT to use

- Ordinary package placement without security questions → [packages.md](packages.md)
- General build workflow → [build.md](build.md)
- ISO-specific signing/release work → [iso.md](iso.md)

## COPR isolation (critical)

Relevant files:
- `build_files/base/03-packages.sh`
- `build_files/shared/copr-helpers.sh`

**Rule:** keep Fedora packages and COPR packages separate.

Why:
- Fedora packages are installed in bulk from trusted repos
- COPR packages must be enabled and installed in isolation
- Mixing them defeats the protection against repo/package injection

Safe pattern:
```bash
FEDORA_PACKAGES=(
  fastfetch
  htop
)

copr_install_isolated "che/nerd-fonts" "nerd-fonts"
copr_install_isolated "ublue-os/packages" "uupd" "oversteer-udev"
```

Validation:
```bash
bash -n build_files/base/03-packages.sh
shellcheck build_files/**/*.sh
```

## Cosign verification

Bluefin verifies upstream containers before building.

From the Justfile:
```bash
just verify-container IMAGE ghcr.io/ublue-os cosign.pub
```

Manual form:
```bash
cosign verify --key cosign.pub ghcr.io/ublue-os/IMAGE:TAG
```

## Secureboot checks

```bash
just secureboot bluefin latest main
```

Use this when changing kernel/module-related inputs or build logic that affects secureboot.

## Supply-chain expectations

- Prefer Fedora repos first
- Prefer known project-owned sources over random third-party repos
- Treat new COPRs as exceptional, not routine
- Do not dilute the isolation rules for convenience

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| COPR package added to `FEDORA_PACKAGES` | security model bypassed | move it to isolated COPR install |
| cosign verify fails | wrong key, tag, or unsigned image | verify key source and image reference |
| secureboot check fails | module/signing mismatch | inspect kernel/module inputs before changing signing logic |

## Lessons learned

<!-- Add reusable security patterns here -->
