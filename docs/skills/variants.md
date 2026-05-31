# Image × Tag × Flavor Matrix

## When to use

- You need the correct image reference
- You are not sure which branch/tag/flavor a workflow touches
- You need to explain Bluefin stream names to another contributor

## When NOT to use

- Building or validating changes → [build.md](build.md)
- Release promotion details → [release.md](release.md)
- Bluefin LTS specifics → [lts.md](lts.md)

## Current repo matrix

### Images

| Image | Purpose |
|---|---|
| `bluefin` | base desktop image |
| `bluefin-dx` | developer-focused variant |

### Flavors

| Flavor | Use case |
|---|---|
| `main` | standard AMD/Intel/open-driver path |
| `nvidia-open` | NVIDIA open kernel module path |

### Streams in this repo

| Branch | Resulting stream/tag |
|---|---|
| `main` | `testing` |
| `latest` | `latest` |
| `stable` | `stable` |
| `testing` | PR target, not published stream |

## OCI naming examples

```text
ghcr.io/projectbluefin/bluefin:testing-main
ghcr.io/projectbluefin/bluefin:stable-nvidia-open
ghcr.io/projectbluefin/bluefin-dx:latest-main
```

## Build matrix touchpoints

- Justfile image map: `Justfile`
- Build workflows: `.github/workflows/build-image-*.yml`
- Reusable matrix logic: `.github/workflows/reusable-build.yml`

## Choosing the right target

| If you need... | Use |
|---|---|
| normal desktop image | `bluefin` |
| dev tooling baked in | `bluefin-dx` |
| default driver stack | `main` |
| NVIDIA open kernel module path | `nvidia-open` |
| pre-promotion testing image | `testing-*` |
| promoted user-facing stream | `latest-*` or `stable-*` |

## Non-obvious patterns

- This repo currently builds `testing`, `latest`, and `stable`; do not assume older stream names are active here
- LTS is a separate repo and workflow model
- For development, do **not** rely on the VS Code Flatpak; use the Homebrew package instead

## Lessons learned

<!-- Add reusable matrix/reference patterns here -->
