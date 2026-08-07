---
name: security
version: "1.1"
last_updated: "2026-08-07"
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
    - Justfile
    - keys/
    - build_files/shared/copr-helpers.sh
    - .github/workflows/vulnerability-scan.yml
---

# Security

## When to Use

- Adding or reviewing a package source.
- Changing signing, verification, secure boot, or release trust behavior.

## When Not to Use

- Routine package or build work with no trust-boundary change: use
  [packages](../packages/SKILL.md) or [build](../build/SKILL.md).
- Adding or rotating a credential — that is a factory-wide policy, see
  [common secrets-policy](https://github.com/projectbluefin/common/blob/main/docs/skills/secrets-policy.md).

## Core Process

1. Read `SECURITY.md` and the affected source before changing anything.
2. Prefer first-party or distribution repositories. Treat a new third-party
   repository as exceptional and justify it in the pull request.
3. Preserve explicit verification and isolation steps — they are boundaries,
   not cleanup.
4. Stop at the Security gate and request human review, per
   [common agentic-model](https://github.com/projectbluefin/common/blob/main/docs/factory/agentic-model.md).
5. Run the focused check plus the default repository gate:

```bash
just check
pre-commit run --all-files
bats tests/unit/copr-helpers_test.bats tests/unit/validate-repos_test.bats
```

## Trust boundaries in this repository

| Boundary | Where it lives |
|---|---|
| Base image is digest-pinned and cosign-verified before build | `Justfile` `build` recipe (`skopeo inspect` → `verify-container … keys/fedora-ostree.pub`) |
| Verification is fatal in CI | `SKIP_BASE_VERIFY=1` is honoured only when `CI != "true"` |
| akmods / akmods-nvidia-open images are cosign-verified | `Justfile` `build` recipe |
| `common` and `brew` layers are digest-pinned | `image-versions.yml`, consumed by `Containerfile` |
| Third-party RPMs stay isolated | `build_files/shared/copr-helpers.sh` |
| Repo state is asserted at the end of the build | `build_files/shared/validate-repos.sh`, `disable-repos.sh` |
| Published images are scanned | `.github/workflows/vulnerability-scan.yml` |
| COPR availability is monitored | `.github/workflows/copr-health-monitor.yml` |

Signing keys are vendored in `keys/` (`fedora-ostree.pub`,
`projectbluefin-common.pub`, `ublue-os-brew.pub`) and updated only by pull
request with justification.

## References

| Reference | Contents |
|---|---|
| [COPR isolation invariant](references/copr-isolation.md) | Why the enable → disable → install sequence is a security boundary |
| [signing and verification](references/signing.md) | Key/keyless cosign modes, vendored keys, secure-boot check, and the promotion identity regexp |

## Red Flags

- Disabling or weakening verification and calling it cleanup.
- Adding a private key, credential, token, or personal registry configuration
  to this repository.
- Replacing a vendored key without a documented rotation reason.
- Bypassing `copr_install_isolated` for "just one package".
- Introducing a package source that is neither Fedora, negativo17
  `fedora-multimedia`, an isolated COPR, Flathub, nor Homebrew.
- Changing the promotion `cosign_identity_regexp` to widen who may sign.

## Verification

```bash
# Vendored keys and their consumers
ls keys/ && grep -n 'keys/' Justfile

# Base-image pin + fatal-verify logic
sed -n '/Verify Base Image with cosign/,/^    fi/p' Justfile

# cosign key vs keyless modes
sed -n '/^verify-container/,/^# Secureboot Check/p' Justfile

# COPR isolation invariant
cat build_files/shared/copr-helpers.sh

# Who may sign a promoted image
grep -n 'cosign_identity_regexp' -A2 .github/workflows/promote-testing-to-main.yml

# Scanned image matrix
grep -n 'image_matrix' .github/workflows/vulnerability-scan.yml
```
