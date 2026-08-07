---
name: worktrees
version: "1.0"
last_updated: 2026-08-06
id: worktrees
one_line_purpose: Do all feature work in isolated git worktrees.
entry_point: docs/skills/worktrees/SKILL.md
category: meta
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [git, worktrees, workflow, agents]
description: >-
  Covers the worktree helper script, branch naming, and cleanup so the main
  checkout stays clean. Use before starting any change, or when the main
  checkout is dirty or on a stale branch.
metadata:
  type: procedure
  source-of-truth:
    - .github/scripts/worktree.sh
    - .github/scripts/install-hooks.sh
    - .gitignore
---

# Worktrees

## Use when

- Starting any change that is not a one-line fix on `testing`.
- The main checkout is dirty, on a stale feature branch, or holds another
  task's work in progress.
- Running an agent: every agent session gets its own worktree so concurrent
  sessions cannot collide in the same working tree.

## Do not use when

- You are already inside a linked worktree. Check first:

```bash
[[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]] && echo "already isolated"
```

## The contract

The main checkout at the repository root stays on `testing` or `main` with a
clean tree. All feature work happens in `.worktrees/<slug>`, branched from
`projectbluefin/testing`.

Two mechanisms enforce this:

- `.worktrees/` is gitignored. A nested `.git` directory stages as a gitlink
  and silently corrupts history, so it must never be tracked.
- The `pre-push` hook refuses to push a feature branch from the main checkout,
  and refuses any remote outside the `projectbluefin` org.
  Install it once after cloning with `bash .github/scripts/install-hooks.sh`.

## Procedure

Create a worktree. The branch is always cut from a freshly fetched
`projectbluefin/testing`, never from whatever the main checkout happens to be
sitting on:

```bash
bash .github/scripts/worktree.sh new fix/my-thing
cd .worktrees/fix-my-thing
```

Work, validate, and push from inside the worktree:

```bash
just check && pre-commit run --all-files
git push projectbluefin fix/my-thing
```

Clean up after the PR merges:

```bash
bash .github/scripts/worktree.sh done fix/my-thing
```

## Housekeeping

List every worktree with its PR state:

```bash
bash .github/scripts/worktree.sh list
```

Remove all worktrees whose PRs are merged or closed. Dirty worktrees are
skipped, never discarded:

```bash
bash .github/scripts/worktree.sh prune
```

Squash merges leave no ancestry, so `git branch --merged` cannot tell you
whether a branch is finished. `worktree.sh` asks the forge via `gh` instead.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `pre-push` rejects a feature branch | Pushing from the main checkout | Move the work into a worktree, or `SKIP_WORKTREE_GUARD=1` for a one-off |
| `worktree already exists` | Stale directory from earlier work | `worktree.sh done <branch>`, or `git worktree prune` if the directory is already gone |
| Untracked `.worktrees/` in `git status` | Hook and ignore rules predate this setup | Confirm `.worktrees/` is in `.gitignore` |
| Uncommitted work blocks `done` | Real changes in the worktree | Commit them, or `git worktree remove <path> --force` to discard |
| A repo script reports zero files | It filters `.worktrees` out by path and is running inside one | Run it from the main checkout, or fix the filter to be checkout-relative |
| `gh pr merge --delete-branch` fails locally after merging | The branch is still checked out in a worktree | The remote merge succeeded; finish with `worktree.sh done <branch>` |

Tooling that excludes `.worktrees/` by absolute path components silently matches
*everything* when it runs from inside a worktree. A validator that passes with a
zero-file count is failing, not succeeding — check the count, not the exit code.

Never use `git add -A` or `git add .`. Stage explicit paths, then verify with
`git status` and `git diff --cached --name-only` before committing.

## Red Flags

- Feature work committed directly in the main checkout.
- A validator or linter reporting suspiciously few files while run in a worktree.
- Removing a worktree with uncommitted changes instead of resolving them.

## Verification

- [ ] `bash .github/scripts/worktree.sh list` shows the expected worktrees.
- [ ] Repository checks were run and reported a non-zero file count.
- [ ] The main checkout is clean and on `testing` or `main`.
