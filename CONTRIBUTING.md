# Contributing to Bluefin

## Prerequisites

Install the tools used by the local validation flow before opening a PR:

- `just` — install with `brew install just` or your OS package manager
- `pre-commit` — install with `pip install pre-commit`, then run `pre-commit install`
- `podman` / `buildah` — required for local image builds; see [docs/build.md](docs/build.md) for build details

`just check` validates Justfile syntax and related script checks. `pre-commit run --all-files` runs the repository linting and formatting hooks.

## Branch and stream workflow

### I want to submit a fix or feature — what do I do?

**PR against `testing`** — that is the default development branch. Never target `main`, `stable`, or `latest` directly.

```bash
gh pr create --repo projectbluefin/bluefin --base testing
```

### Before you open a PR

```bash
just check                    # Justfile and script syntax validation
pre-commit run --all-files    # Lint / format checks
```

Both must pass. For local image build requirements and commands, see [docs/build.md](docs/build.md). The PR template has a checklist — fill it out honestly.

### Merge method

Squash merge only. Keep your PR branch tidy; the commit message on the squash is what matters.

## Stream promotion

Every Tuesday at 06:00 UTC the `weekly-testing-promotion` workflow:
1. Verifies smoke e2e tests have passed on the `testing` HEAD
2. Runs the full developer + vanilla-gnome e2e suite
3. Fast-forwards `latest` and `stable` branches to `testing`
4. Triggers the `stable` and `latest` image builds

Changes land in `testing` → promoted to `stable`/`latest` weekly on CI green.

## Branching for a new Fedora version

- Wait for the Fedora Beta announcement
- PR `ublue-os/akmods` for the new version
- Bump `testing_version` in `Justfile`
- Handle third-party repo breakage

## Promoting to a new `:stable` / `:latest`

- Wait for the official Fedora release (package freeze lifted)
- Wait for coreos:stable (~2 weeks post-Fedora) → PR `ublue-os/akmods`
- Bump workflow and Justfile version references in `testing`
- Create a new `stable-f$N` branch and update branch protection rules

## Stream reference

| | `:testing` | `:latest` | `:stable` |
|---|---|---|---|
| Built from | `testing` branch | `latest` branch | `stable` branch |
| Kernel | Fedora default | Fedora default, pinned on bad regressions | coreos-stable, pinned on regressions |
| Published | On every merge to `testing` | Weekly promotion | Weekly promotion + emergency manual |
| Who should use it | Testers, developers | Enthusiasts | Regular users |

## Conventional commits

Every commit message and PR title must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
feat(packages): add fzf to base brew
fix(ci): correct digest variable name in reusable-build
chore(deps): update ghcr.io/projectbluefin/common digest
```

## AI-assisted contributions

If you used an AI tool to write any part of this PR, add the attribution footer:

```
Assisted-by: <Model Name> via <Tool Name>
```

Check the box in the PR template confirming you take responsibility for the change.

## Issue lifecycle

Issues flow through `filed → approved → queued → claimed → done` via the bonedigger bot.

- Comment `/claim` to take an issue from the queue
- Comment `/approve` (maintainers only) to move an issue to the queue
- Comment `/unclaim` to return an issue you can no longer work on

See [docs/workflow.md](docs/workflow.md) for the full lifecycle reference.
