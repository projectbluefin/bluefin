# Contributing

Cross-repo procedure is canonical in
[`common/docs/factory/agentic-model.md`](https://github.com/projectbluefin/common/blob/main/docs/factory/agentic-model.md).
This document covers only what applies to this repository.

## Before editing

Read [`../AGENTS.md`](../AGENTS.md), then load the matching skill from
[`skills/index.md`](skills/index.md). Do the work in an isolated worktree cut
from the remote `testing` branch, not in the main checkout and not on an
unrelated local commit:

```bash
bash .github/scripts/worktree.sh new <branch>
```

See [`skills/worktrees/SKILL.md`](skills/worktrees/SKILL.md).

## Required local checks

```bash
just check
pre-commit run --all-files
```

For shell-library or setup-hook changes:

```bash
just test-unit
```

Run a full image build only when the change affects image assembly. The full
validation matrix is in [`qa.md`](qa.md).

## Staging audit

Never use `git add -A` or `git add .`. Stage only intended paths, then confirm
what is staged before committing:

```bash
git status
git diff --cached --name-only
```

Nested `.git` directories from worktrees or auxiliary clones stage as gitlinks
and corrupt history; `pr-validation.yml` fails on gitlinks that are not declared
in `.gitmodules`.

## Pull requests

- Target `testing`. Never open a content PR against `main` — `pr-validation.yml`
  fails such a pull request. See the branch-target table in
  [`common`](https://github.com/projectbluefin/common/blob/main/docs/factory/agentic-model.md#branch-targets).
- Check for an existing pull request before opening a new one:
  `gh pr list --repo projectbluefin/bluefin --state open --search "<topic>"`.
- Squash merge only.
- Use Conventional Commits for titles and commits; release notes are generated
  from them by [`cliff.toml`](../cliff.toml).
- One logical change per pull request, even when the diff is small.
- Link the issue with `Closes #NNN`.
- Do not include secrets or generated artifacts, and never add a new secret,
  token, or credential — that is a human decision.
- Describe exactly what was tested.
- Update the closest skill when the change reveals a reusable procedure.
- Do not self-approve or self-merge.
- Ask a human before opening a pull request autonomously; opening one is not an
  implied part of a task.

After pushing, verify CI: `gh run list --repo projectbluefin/bluefin --limit 5`.

AI-assisted commits must include both attribution trailers:

```text
Assisted-by: <Model> via GitHub Copilot
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

Attribution is a convention enforced at commit time, not a blocking CI check.

## Sensitive paths

Changes under `.github/workflows/`, `Justfile`, or `build_files/` require
maintainer review before merge.

## Scope discipline

Read the affected source before changing documentation. Prefer the smallest
change that fully satisfies the requirement. Shared behavior belongs in its
shared source; do not duplicate implementation in a caller or a skill.
