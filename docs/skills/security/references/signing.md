# Signing and verification

Reference for [`../SKILL.md`](../SKILL.md). Every value below is derived from
`Justfile`, `keys/`, and `.github/workflows/`. Re-derive before quoting it —
see [Verification](#verification).

## Vendored public keys

`keys/` holds the only trust anchors this repository ships:

| Key | Verifies |
|---|---|
| `fedora-ostree.pub` | `quay.io/fedora-ostree-desktops/silverblue` base image |
| `ublue-os-brew.pub` | Default key for `just verify-container` (`ghcr.io/ublue-os` registry), e.g. the akmods images |
| `projectbluefin-common.pub` | `ghcr.io/projectbluefin/common` |

Update a key only by pull request, with the rotation reason in the description.
Never add a private key or credential to this repository.

## `just verify-container`

`verify-container container registry key` is the single verification entry
point. Its behavior:

- Requires cosign **v3+** to verify Sigstore Bundle v0.3 signatures; it
  installs the pinned `COSIGN_VERSION` when the runner's cosign is pre-v3.
- With `key=keyless`, it verifies against
  `--certificate-identity-regexp="https://github.com/projectbluefin/(common|actions)/.github/workflows/"`
  and the GitHub Actions OIDC issuer.
- Otherwise it verifies with `cosign verify --key`, defaulting to
  `keys/ublue-os-brew.pub`.
- Retries up to 5 times with a 10s delay for transient registry errors, then
  exits non-zero.

## Base image pinning

`just build` resolves the `silverblue` tag to a digest with `skopeo inspect`
(5 attempts), then verifies that digest with `keys/fedora-ostree.pub` and
passes the pinned `BASE_IMAGE_REF` into the build. A verification failure is
fatal. `SKIP_BASE_VERIFY=1` skips it **only** when `CI` is not `true`; that
escape hatch is for local development and must never be set in a workflow.

`common` and `brew` are consumed by digest from `image-versions.yml`, which
`Containerfile` references as `${IMAGE}@${IMAGE_SHA}`.

## Secure boot

`just secureboot <image> <tag> <flavor>` extracts `/usr/lib/modules/<kernel>/vmlinuz`
from the built image and runs `sbverify` against the `ublue-os/akmods`
`public_key.der` and `public_key_2.der` certificates. It is invoked
automatically from `just rechunk` when `pipeline=1`.

## Release signing identity

`promote-testing-to-main.yml` passes
`cosign_identity_regexp: ^https://github\.com/projectbluefin/(bluefin|actions)/\.github/workflows/`
to the reusable promotion workflow. Widening that regexp widens who may sign a
promoted image and is a Security-gate change.

The image build and signing itself happen in
`projectbluefin/actions/.github/workflows/reusable-build.yml@v1`; this
repository grants it `id-token: write` and `attestations: write` in
`build-image-testing.yml`. Read the reusable workflow before describing what it
signs.

## Verification

```bash
ls keys/
sed -n '/^verify-container/,/^# Secureboot Check/p' Justfile
sed -n '/^secureboot/,/^# Get Fedora Version/p' Justfile
grep -n 'cosign_identity_regexp' -A2 .github/workflows/promote-testing-to-main.yml
grep -n 'id-token\|attestations' .github/workflows/build-image-testing.yml
gh api repos/projectbluefin/actions/contents/.github/workflows/reusable-build.yml --jq .html_url
```
