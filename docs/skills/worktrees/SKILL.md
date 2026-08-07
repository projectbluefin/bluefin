---
name: worktrees
description: Keep the main checkout clean by doing all feature work in isolated git worktrees. Use before starting any change, or when the tree is dirty.
metadata:
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
- The `pre-push` hook refuses to push a feature branch from the main checkout.
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

Never use `git add -A` or `git add .`. Stage explicit paths, then verify with
`git status` and `git diff --cached --name-only` before committing.
