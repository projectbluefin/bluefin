# Image × Tag × Flavor Matrix

## When to use

- You need the correct image reference
- You are not sure which branch/tag/flavor a workflow touches
- You need to explain Bluefin stream names to another contributor

## When NOT to use

- Building or validating changes → [build.md](build.md)
- Release promotion details → [release.md](release.md)
- Bluefin LTS specifics → `projectbluefin/bluefin-lts` repo

## Current repo matrix

### Images

| Image | Purpose |
|---|---|
| `bluefin` | base desktop image |

### Flavors

| Flavor | Use case |
|---|---|
| `main` | standard AMD/Intel/open-driver path |
| `nvidia` | NVIDIA open kernel module path (published image: `bluefin-nvidia`) |

### Streams in this repo

| Branch | Build runs? | Published tag |
|---|---|---|
| `testing` | Yes | None directly — `:testing` tag applied by `post-testing-e2e.yml` only when triggered by a `main` push |
| `main` | Yes | `:testing` (via `post-testing-e2e.yml`) + `:stable` (via `execute-release.yml` on promotion commit) |
| `stable` | No build workflow | Legacy branch; exists in origin but not built |
| `latest` | No build workflow | Legacy branch; exists in origin but not built |

## OCI naming examples

```text
ghcr.io/projectbluefin/bluefin:testing-main
ghcr.io/projectbluefin/bluefin:stable-nvidia
```

## Build matrix touchpoints

- Justfile image map: `Justfile`
- Build workflows: `.github/workflows/build-image-*.yml`
- Reusable matrix logic: `projectbluefin/actions/.github/workflows/reusable-build.yml` (centralized — not a local file)

## Choosing the right target

| If you need... | Use |
|---|---|
| normal desktop image | `bluefin` |
| default driver stack | `main` |
| NVIDIA open kernel module path | `nvidia` (image: `bluefin-nvidia`) |
| pre-promotion testing image | `testing` |
| promoted user-facing stream | `stable` |

## Non-obvious patterns

- This repo builds two streams: `:testing` (daily, promoted from `testing` branch via `main`) and `:stable` (daily automated release via factory)
- `:testing` is applied by `post-testing-e2e.yml` and only when triggered by a push to `main` — not by pushes to `testing`
- LTS is a separate repo and workflow model

## Lessons learned

<!-- Add reusable matrix/reference patterns here -->
