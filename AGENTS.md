# AGENTS.md

## Purpose

This repository builds and validates a bootable OCI desktop image. Start here,
then load only the documentation needed for the task.

## Documentation navigation

1. Read this file.
2. Read [`docs/skills/index.md`](docs/skills/index.md).
3. Load one matching `docs/skills/<name>/SKILL.md`.
4. Load linked references only when the selected skill requires them.
5. Treat source files and workflow definitions as authoritative over summaries.

Stable guidance:

- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Contribution policy: [`docs/contributing.md`](docs/contributing.md)
- Validation and QA: [`docs/qa.md`](docs/qa.md)
- Release model: [`docs/release.md`](docs/release.md)
- Issue lifecycle: [`docs/workflow.md`](docs/workflow.md)

## Agent fast path

- Read source before asserting project-internal facts such as image names, tags,
  or workflow outputs. Use `gh api` to inspect workflows, not memory.
- Look up external tool documentation through Context7 before quoting it.
- When a session surfaces a non-obvious pattern or workaround, update the
  matching skill in the same change.

## Factory contracts

This repository is part of the `projectbluefin` factory. Cross-repo procedure is
canonical in `projectbluefin/common`; do not restate it here, link it.

| Topic | Canonical source |
|---|---|
| Cross-repo agent hard rules | [`common/docs/factory/agentic-model.md`](https://github.com/projectbluefin/common/blob/main/docs/factory/agentic-model.md) |
| Issue lifecycle and labels | [`common/docs/skills/label-workflow.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md) |
| Human decision gates | [`common/docs/skills/human-gates.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/human-gates.md) |
| Skill improvement mandate | [`common/docs/skills/skill-improvement.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/skill-improvement.md) |
| `ujust report` intake | [`common/docs/skills/bonedigger.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/bonedigger.md) |

Stop and request human input at the Design, Security, Breakage, or Merge gate.

## Common validation

Run the lightest relevant checks:

```bash
just check
pre-commit run --all-files
```

For shell-library or setup-hook changes:

```bash
bats tests/unit/
```

Run a full image build only when image assembly or container behavior changed:

```bash
just build <image> <stream> <flavor>
just clean
```

Install the repository hook once after cloning:

```bash
bash .github/scripts/install-hooks.sh
```

Do feature work in an isolated worktree, never in the main checkout. The
`pre-push` hook enforces this. See [worktrees](docs/skills/worktrees/SKILL.md).

```bash
bash .github/scripts/worktree.sh new fix/my-thing
```

## Source-of-truth rules

- `Justfile` defines local commands.
- `Containerfile` defines image stages.
- `build_files/` defines build logic.
- `.github/workflows/` defines CI and release triggers.
- `tests/` defines executable regression coverage.
- Documentation must not contradict source files.
- If behavior changes, update the closest matching skill in the same change.

## Change flow

- Branch from the remote target, not from whatever is checked out:
  `git fetch projectbluefin testing && git checkout -b <branch> projectbluefin/testing`.
- Push to the `projectbluefin` remote explicitly; a pre-push hook blocks `origin`.
- All pull requests target `testing`. Never open a content PR against `main`.
- One logical change per pull request; squash merge only.
- Check for an existing pull request before opening a new one:
  `gh pr list --repo projectbluefin/bluefin --state open --search "<topic>"`.
- Every AI-authored commit carries both attribution trailers:

  ```text
  Assisted-by: <Model> via GitHub Copilot
  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
  ```

## Boundaries

- Do not modify generated artifacts, caches, or worktree contents.
- Never create, propose, or add new secrets, tokens, PATs, or app credentials.
  Reach for documented git and GitHub primitives first, then ask a human.
- Do not add credentials or personal infrastructure details.
- Do not change CI or release behavior without reading the affected workflow.
- Do not weaken package-source, signing, or verification boundaries.
- Do not run expensive image builds for documentation-only changes.
- Never use `git add -A` or `git add .`; stage only intended paths and inspect
  `git diff --cached --name-only` before committing.
- Never perform any write action against `ublue-os/*` or any repository outside
  the `projectbluefin` org. Read-only inspection is permitted.
- Keep documentation generic, source-linked, and reusable.
- Do not create client-specific agent instructions or tool-specific duplicates.

## Completion

Before declaring work complete:

1. Run relevant validation commands.
2. Check links and changed paths.
3. Update the matching skill when a reusable fact or procedure changes.
4. Keep the change narrowly scoped.
