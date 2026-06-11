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

> **Invariant detail:** the enable → disable → install three-step sequence is a
> security boundary, not cleanup. See [`copr-security.md`](copr-security.md) for
> the full reasoning and safe/unsafe patterns.

## Cosign verification

Bluefin verifies upstream containers before building.

From the Justfile:
```bash
just verify-container IMAGE ghcr.io/projectbluefin cosign.pub
```

Manual form:
```bash
cosign verify --key cosign.pub ghcr.io/projectbluefin/IMAGE:TAG
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

## Signing modes in shared actions

The `bootc-build/sign-and-publish` action supports two signing modes:

| Mode | Used by | How it works |
|---|---|---|
| `keyless` | Bluefin | OIDC → Fulcio certificate → Rekor transparency log |
| `key-based` | Aurora, Bazzite | `SIGNING_SECRET` → cosign sign with private key |

Usage in workflows:
```yaml
- uses: projectbluefin/actions/bootc-build/sign-and-publish@v1
  with:
    mode: keyless          # or "key-based"
    image: ghcr.io/projectbluefin/bluefin:stable
    # key-based mode only:
    # signing-secret: ${{ secrets.SIGNING_SECRET }}
```

Keyless is preferred for new projects. Key-based exists for backwards compatibility with existing Aurora/Bazzite infrastructure.

## Lessons learned

<!-- Add reusable security patterns here -->
