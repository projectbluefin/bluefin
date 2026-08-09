# Signing and verification

Use the verification commands already defined in the `Justfile` and affected
workflow. Confirm the key, image reference, digest, and expected signature mode
from source before changing any trust behavior.

Do not add private keys, credentials, or personal registry configuration to this
repository.

## Signature format: legacy `.sig` tag, not the new bundle format

Bluefin images must be signed so that **podman, skopeo and `bootc switch` can verify
them** — not merely so that `cosign verify` passes. Those are different requirements,
and conflating them has already cost the project months of unsigned images.

`containers/image`, the library behind all three tools, discovers a signature only at
the legacy tag:

```
sha256-<image-digest>.sig
```

It does **not** consult the OCI 1.1 referrers API — and GHCR does not implement
`/referrers` anyway, returning 404. So a signature written in Sigstore's newer bundle
format (attached as an OCI referrer under a bare `sha256-<digest>` tag) is invisible to
a `policy.json` `sigstoreSigned` entry, even though it is a perfectly valid signature.

**cosign 3.x flipped `--new-bundle-format` to default `true`.** Every image built after
that default reached our pipeline (~2026-06-08) is signed in a way podman cannot see.
See projectbluefin/common#977 for the inventory and projectbluefin/actions#420 for the
fix.

### Why CI did not catch it

`cosign verify` accepts **both** formats. The signing workflow signed, verified, and
reported success on every run throughout the regression. Verification with cosign is
therefore *not* sufficient evidence that an image is usable by our own consumers.

### What to check

When touching anything in the signing path, confirm the legacy tag exists in the
registry rather than trusting a green `cosign verify`:

```bash
DIGEST=$(skopeo inspect --format '{{.Digest}}' docker://ghcr.io/projectbluefin/bluefin:stable)
skopeo inspect "docker://ghcr.io/projectbluefin/bluefin:${DIGEST/:/-}.sig" >/dev/null \
  && echo "signature visible to podman/bootc" \
  || echo "NOT verifiable by podman/bootc"
```

`projectbluefin/actions` enforces this automatically in `sign-and-publish` via the
`Assert legacy .sig tag exists` step. Do not set `new-bundle-format: "true"` on that
action unless every consumer of the image verifies with cosign rather than with
podman/bootc policy.
