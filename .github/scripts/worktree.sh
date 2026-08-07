#!/usr/bin/env bash
# Worktree helper: keep the main checkout clean by doing all feature work in
# isolated worktrees under .worktrees/.
#
#   bash .github/scripts/worktree.sh new fix/my-thing
#   bash .github/scripts/worktree.sh list
#   bash .github/scripts/worktree.sh done fix/my-thing
#   bash .github/scripts/worktree.sh prune

set -euo pipefail

REMOTE="projectbluefin"
BASE_BRANCH="testing"

# --show-toplevel returns the *current* worktree's root, so it cannot identify
# the main checkout when this script runs from inside a worktree. The common
# git dir always lives in the main checkout, so derive the root from that.
GIT_COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
ROOT="$(dirname "$GIT_COMMON")"
WORKTREE_DIR="${ROOT}/.worktrees"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

slugify() {
  printf '%s' "${1//\//-}"
}

require_remote() {
  git remote get-url "$REMOTE" >/dev/null 2>&1 ||
    die "no '${REMOTE}' remote. Add it: git remote add ${REMOTE} git@github.com:projectbluefin/bluefin.git"
}

# A branch is disposable once its PR is MERGED or CLOSED. Squash merges leave no
# ancestry, so `git branch --merged` cannot answer this; ask the forge instead.
pr_state() {
  local branch="$1"
  command -v gh >/dev/null 2>&1 || return 1
  gh pr list --repo projectbluefin/bluefin --head "$branch" --state all \
    --json state --jq '.[0].state' 2>/dev/null
}

cmd_new() {
  local branch="${1:-}"
  [[ -n "$branch" ]] || die "usage: worktree.sh new <branch-name>"
  require_remote

  local path
  path="${WORKTREE_DIR}/$(slugify "$branch")"
  [[ -e "$path" ]] && die "worktree already exists: ${path}"

  echo "Fetching ${REMOTE}/${BASE_BRANCH}..."
  git fetch "$REMOTE" "$BASE_BRANCH" --quiet

  mkdir -p "$WORKTREE_DIR"
  git worktree add "$path" -b "$branch" "${REMOTE}/${BASE_BRANCH}"

  echo
  echo "Worktree ready: ${path}"
  echo "Branch '${branch}' is based on ${REMOTE}/${BASE_BRANCH}."
  echo "  cd ${path}"
  echo "Push with: git push ${REMOTE} ${branch}"
}

cmd_list() {
  local path branch state
  git worktree list --porcelain |
    awk '/^worktree /{p=$2} /^branch /{sub("refs/heads/","",$2); print p"\t"$2}' |
    while IFS=$'\t' read -r path branch; do
      [[ "$path" == "$ROOT" ]] && { printf '%-50s %-40s %s\n' "$path" "$branch" "(main checkout)"; continue; }
      state="$(pr_state "$branch" || true)"
      printf '%-50s %-40s %s\n' "$path" "$branch" "PR: ${state:-none}"
    done
}

remove_worktree() {
  local path="$1" branch="$2"
  git worktree remove "$path" --force
  git branch -D "$branch" 2>/dev/null || true
  echo "Removed ${path} (branch ${branch})"
}

cmd_done() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "usage: worktree.sh done <branch-name>"

  local path
  path="${WORKTREE_DIR}/$(slugify "$target")"
  [[ -d "$path" ]] || die "no worktree at ${path}"

  local branch
  branch="$(git -C "$path" branch --show-current)"

  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    die "worktree has uncommitted changes: ${path}
Commit or discard them first, or run: git worktree remove ${path} --force"
  fi

  remove_worktree "$path" "$branch"
}

cmd_prune() {
  git worktree prune

  local path branch state
  while IFS=$'\t' read -r path branch; do
    [[ "$path" == "$ROOT" ]] && continue
    [[ "$path" == "$WORKTREE_DIR"/* ]] || continue

    state="$(pr_state "$branch" || true)"
    case "$state" in
      MERGED | CLOSED)
        if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
          echo "SKIP ${path}: PR ${state} but worktree is dirty"
          continue
        fi
        remove_worktree "$path" "$branch"
        ;;
      *)
        echo "KEEP ${path} (branch ${branch}, PR: ${state:-none})"
        ;;
    esac
  done < <(git worktree list --porcelain |
    awk '/^worktree /{p=$2} /^branch /{sub("refs/heads/","",$2); print p"\t"$2}')
}

case "${1:-}" in
  new) shift && cmd_new "$@" ;;
  list) shift && cmd_list "$@" ;;
  done) shift && cmd_done "$@" ;;
  prune) shift && cmd_prune "$@" ;;
  *)
    cat >&2 <<'USAGE'
usage: worktree.sh <command>

  new <branch>    Create a worktree in .worktrees/ based on projectbluefin/testing
  list            List worktrees with their PR state
  done <branch>   Remove a worktree and delete its local branch
  prune           Remove every worktree whose PR is merged or closed
USAGE
    exit 1
    ;;
esac
