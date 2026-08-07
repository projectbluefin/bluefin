---
name: variants
version: "1.1"
last_updated: "2026-08-07"
id: variants
one_line_purpose: Determine the correct image, stream, flavor, branch, and target.
entry_point: docs/skills/variants/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [variants, images, streams, tags]
description: >-
  Maps image names, streams, flavors, and branches to their published tags
  and build workflows. Use when choosing an image reference for a command,
  report, or workflow dispatch.
metadata:
  type: reference
  source-of-truth:
    - Justfile
    - image-versions.yml
    - .github/workflows/build-image-testing.yml
    - .github/workflows/promote-testing-to-main.yml
---

# Variants

## When to Use

- Choosing an image, tag, or flavor for a `just` command, report, or dispatch.
- Deciding which branch a change or a published tag belongs to.

## When Not to Use

- Implementation work unrelated to image targeting.
- Registry-wide questions across the factory: see
  [common image-registry](https://github.com/projectbluefin/common/blob/main/docs/skills/image-registry.md).

## Local build matrix

`Justfile` defines three maps, and `just validate` rejects any combination
outside them:

| Map | Accepted values |
|---|---|
| `images` | `bluefin` |
| `tags` | `testing` |
| `flavors` | `main`, `nvidia` |

`just image_name <image> <tag> <flavor>` resolves the published name: a flavor
matching `main` yields `bluefin`, any other flavor yields `<image>-<flavor>`
(so `nvidia` → `bluefin-nvidia`).

The recipe signature is `build $image $tag $flavor` — the second positional is
a **tag**, not a stream name:

```bash
just build bluefin testing main
just build bluefin testing nvidia
```

## CI matrix

- `build-image-testing.yml` calls `reusable-build.yml@v1` with
  `image_flavors: ["main", "nvidia"]` (narrowed by `detect-changes` on pull
  requests), `stream_name: testing`, and `publish_stream_tag: "false"`.
- `:testing` is moved separately by `post-testing-e2e.yml`'s
  `promote-to-testing` job via `skopeo copy` on the verified digest, and only
  when `workflow_run.head_branch == 'main'`.
- `promote-testing-to-main.yml` promotes the variants
  `[{"image":"bluefin"},{"image":"bluefin-nvidia"}]`.
- `vulnerability-scan.yml` scans `bluefin` and `bluefin-nvidia` at
  `default_tag: testing`.

## Pinned upstream images

`image-versions.yml` is the single source of truth for the layers this image
consumes — `ghcr.io/projectbluefin/common` and `ghcr.io/ublue-os/brew`, each
with an explicit digest. `just build` reads it with `yq`; `Containerfile`
consumes them as `${IMAGE}@${IMAGE_SHA}`.

## Red Flags

- Inferring a published tag from prose instead of the workflow.
- Passing a stream name where the `Justfile` expects a tag.
- Assuming `stable`, `lts`, `beta`, or `gts` are buildable here — `tags` only
  contains `testing`.
- Editing `image-versions.yml` digests by hand instead of letting
  `track-common.yml` update them.

## Verification

```bash
# Local image / tag / flavor maps
sed -n '1,20p' Justfile

# How a flavor becomes a published image name
sed -n '/^image_name /,/echo "\${image_name}"/p' Justfile

# CI flavor matrix and stream
grep -n 'image_flavors\|stream_name\|publish_stream_tag' .github/workflows/build-image-testing.yml

# Promotion and scan variants
grep -n 'variants:' -A2 .github/workflows/promote-testing-to-main.yml
grep -n 'image_matrix' .github/workflows/vulnerability-scan.yml

# Pinned upstream layers
cat image-versions.yml

# What is actually published
skopeo list-tags docker://ghcr.io/projectbluefin/bluefin
```
