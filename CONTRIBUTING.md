# Contributing to Bluefin

## Prerequisites

Install the tools used by the local validation flow before opening a PR:

- `just` — install with `brew install just` or your OS package manager
- `pre-commit` — install with `pip install pre-commit`, then run `pre-commit install`
- `podman` / `buildah` — required for local image builds; see [docs/build.md](docs/build.md) for build details

`just check` validates Justfile syntax and related script checks. `pre-commit run --all-files` runs the repository linting and formatting hooks.

## After cloning

```bash
bash .github/scripts/install-hooks.sh   # Install pre-push hook (run once after cloning)
```

> **⚠️ Git remote trap:** A pre-push hook blocks any push to a remote named `origin`. Always push via: `git push projectbluefin <branch>`. Verify with `git remote -v` before any push.

## Branch and stream workflow

**PR against `testing`** — that is the default development branch. Never target `main` directly.

```bash
gh pr create --repo projectbluefin/bluefin --base testing
```

### Before you open a PR

```bash
just check                    # Justfile and script syntax validation
pre-commit run --all-files    # Lint / format checks
```

Both must pass. See [docs/build.md](docs/build.md) for local build instructions. The PR template has a checklist — fill it out honestly.

### Merge method

Squash merge only.

## Stream promotion

The factory is fully automated. Every PR that merges to `testing` enters the promotion pipeline:

1. `testing` image is built and tagged `:testing`
2. `promote-testing-to-main.yml` runs daily at 04:00 UTC — squash-merges `testing` → `main` via merge queue
3. `execute-release.yml` fires on push to `main` — re-tags `:testing` → `:stable`, generates release notes

No human approvals required. See [docs/skills/ci.md](docs/skills/ci.md) for the full pipeline.

## Stream reference

| | `:testing` | `:stable` |
|---|---|---|
| Built from | `testing` + `main` branches | Promoted from `:testing` daily |
| Published | After daily promotion cycle (push to `main` triggers the tag) | Daily automated promotion |
| Who should use it | Testers, developers | Regular users |

## Branching for a new Fedora version

- Wait for the Fedora Beta announcement
- PR `projectbluefin/akmods` for the new version
- Bump `testing_version` in `Justfile`
- Handle third-party repo breakage

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
