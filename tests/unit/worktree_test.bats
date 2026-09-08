#!/usr/bin/env bats
# Unit tests for .github/scripts/worktree.sh.
# Run with: bats tests/unit/worktree_test.bats
#
# The script is exercised against a throwaway git repository with a local bare
# "projectbluefin" remote and a stubbed `gh`, so no network call is made and
# the real checkout is never touched.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
WORKTREE_SH="${SCRIPT_DIR}/../../.github/scripts/worktree.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/worktree.${BATS_TEST_NUMBER:-0}.$$"
    REMOTE_REPO="${TEST_ROOT}/remote.git"
    REPO="${TEST_ROOT}/repo"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    GH_LOG="${TEST_ROOT}/gh.log"
    GH_STATE_DIR="${TEST_ROOT}/gh-state"

    mkdir -p "${STUB_BIN}" "${GH_STATE_DIR}"

    export HOME="${TEST_ROOT}"
    export GIT_CONFIG_GLOBAL="${TEST_ROOT}/gitconfig-global"
    export GIT_CONFIG_SYSTEM="${TEST_ROOT}/gitconfig-system"
    export GIT_CONFIG_NOSYSTEM=1
    : > "${GIT_CONFIG_GLOBAL}"
    : > "${GIT_CONFIG_SYSTEM}"
    git config --file "${GIT_CONFIG_GLOBAL}" user.email "test@example.com"
    git config --file "${GIT_CONFIG_GLOBAL}" user.name "Test"
    git config --file "${GIT_CONFIG_GLOBAL}" init.defaultBranch testing

    git init --quiet --bare --initial-branch=testing "${REMOTE_REPO}"

    git init --quiet --initial-branch=testing "${REPO}"
    git -C "${REPO}" commit --quiet --allow-empty -m "root"
    git -C "${REPO}" remote add projectbluefin "${REMOTE_REPO}"
    git -C "${REPO}" push --quiet projectbluefin testing

    # `gh pr list ... --head <branch>` answers with the state recorded for that
    # branch under GH_STATE_DIR; unknown branches produce empty output, which is
    # what the real gh does for a branch with no PR.
    cat > "${STUB_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_LOG}"
branch=""
prev=""
for arg in "$@"; do
    [[ "$prev" == "--head" ]] && branch="$arg"
    prev="$arg"
done
state_file="${GH_STATE_DIR}/${branch//\//__}"
if [[ -n "${GH_FAIL:-}" ]]; then
    exit 1
fi
if [[ -n "$branch" && -f "$state_file" ]]; then
    cat "$state_file"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/gh"

    export GH_LOG GH_STATE_DIR
    export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
    # Linked worktrees hold locks on the sandbox; force-remove the whole tree.
    rm -rf "${TEST_ROOT}"
}

# Run worktree.sh from inside the sandbox checkout (or a worktree of it).
wt() {
    wt_from "${REPO}" "$@"
}

wt_from() {
    local dir="$1"
    shift
    local args=""
    local a
    for a in "$@"; do
        args+=" $(printf '%q' "$a")"
    done
    run bash -c "cd '${dir}' && bash '${WORKTREE_SH}'${args} 2>&1"
}

set_pr_state() {
    printf '%s\n' "$2" > "${GH_STATE_DIR}/${1//\//__}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Dispatch
# ──────────────────────────────────────────────────────────────────────────────

@test "worktree: no command prints usage and exits 1" {
    wt
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage: worktree.sh <command>"* ]]
}

@test "worktree: unknown command prints usage and exits 1" {
    wt bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage: worktree.sh <command>"* ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# new
# ──────────────────────────────────────────────────────────────────────────────

@test "worktree new: without a branch name fails with usage" {
    wt new
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage: worktree.sh new <branch-name>"* ]]
}

@test "worktree new: creates a worktree under .worktrees/ on a new branch" {
    wt new fix/thing
    [ "$status" -eq 0 ]
    [ -d "${REPO}/.worktrees/fix-thing" ]

    run git -C "${REPO}/.worktrees/fix-thing" branch --show-current
    [ "$output" = "fix/thing" ]
}

@test "worktree new: slugifies every slash in the branch name" {
    wt new feat/deep/nested
    [ "$status" -eq 0 ]
    [ -d "${REPO}/.worktrees/feat-deep-nested" ]
}

@test "worktree new: bases the branch on projectbluefin/testing" {
    git -C "${REPO}" commit --quiet --allow-empty -m "local-only work"

    wt new fix/based
    [ "$status" -eq 0 ]

    local base head
    base="$(git -C "${REPO}" rev-parse projectbluefin/testing)"
    head="$(git -C "${REPO}/.worktrees/fix-based" rev-parse HEAD)"
    [ "$base" = "$head" ]
}

@test "worktree new: refuses to clobber an existing worktree path" {
    wt new fix/thing
    [ "$status" -eq 0 ]

    wt new fix/thing
    [ "$status" -eq 1 ]
    [[ "$output" == *"worktree already exists"* ]]
}

@test "worktree new: fails when the projectbluefin remote is missing" {
    git -C "${REPO}" remote remove projectbluefin

    wt new fix/thing
    [ "$status" -eq 1 ]
    [[ "$output" == *"no 'projectbluefin' remote"* ]]
    [ ! -d "${REPO}/.worktrees/fix-thing" ]
}

@test "worktree new: works when invoked from inside an existing worktree" {
    wt new fix/first
    [ "$status" -eq 0 ]

    wt_from "${REPO}/.worktrees/fix-first" new fix/second
    [ "$status" -eq 0 ]

    # Paths are anchored on the main checkout, not the calling worktree.
    [ -d "${REPO}/.worktrees/fix-second" ]
    [ ! -d "${REPO}/.worktrees/fix-first/.worktrees" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# list
# ──────────────────────────────────────────────────────────────────────────────

@test "worktree list: marks the main checkout" {
    wt list
    [ "$status" -eq 0 ]
    [[ "$output" == *"(main checkout)"* ]]
}

@test "worktree list: reports the PR state reported by gh" {
    wt new fix/thing
    set_pr_state fix/thing OPEN

    wt list
    [ "$status" -eq 0 ]
    [[ "$output" == *"fix/thing"* ]]
    [[ "$output" == *"PR: OPEN"* ]]
}

@test "worktree list: reports 'none' for a branch with no PR" {
    wt new fix/thing

    wt list
    [ "$status" -eq 0 ]
    [[ "$output" == *"PR: none"* ]]
}

@test "worktree list: survives a gh failure instead of aborting" {
    wt new fix/thing

    run bash -c "cd '${REPO}' && GH_FAIL=1 bash '${WORKTREE_SH}' list 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PR: none"* ]]
}

@test "worktree list: handles worktree paths containing spaces" {
    # git ref names cannot contain spaces, but the worktree *path* can, so the
    # porcelain parser must not whitespace-split the worktree line.
    mkdir -p "${REPO}/.worktrees"
    git -C "${REPO}" worktree add --quiet -b fix/spacey "${REPO}/.worktrees/has space" >/dev/null 2>&1
    set_pr_state fix/spacey OPEN

    wt list
    [ "$status" -eq 0 ]
    [[ "$output" == *".worktrees/has space"* ]]
    [[ "$output" == *"fix/spacey"* ]]
    [[ "$output" == *"PR: OPEN"* ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# done
# ──────────────────────────────────────────────────────────────────────────────

@test "worktree done: without a branch name fails with usage" {
    wt done
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage: worktree.sh done <branch-name>"* ]]
}

@test "worktree done: fails when there is no worktree for the branch" {
    wt done fix/missing
    [ "$status" -eq 1 ]
    [[ "$output" == *"no worktree at"* ]]
}

@test "worktree done: removes the worktree and deletes the local branch" {
    wt new fix/thing

    wt done fix/thing
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed"* ]]
    [ ! -d "${REPO}/.worktrees/fix-thing" ]

    run git -C "${REPO}" rev-parse --verify --quiet "refs/heads/fix/thing"
    [ "$status" -ne 0 ]
}

@test "worktree done: refuses to remove a worktree with uncommitted changes" {
    wt new fix/thing
    printf 'dirty\n' > "${REPO}/.worktrees/fix-thing/scratch.txt"

    wt done fix/thing
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
    [ -d "${REPO}/.worktrees/fix-thing" ]
}

@test "worktree done: accepts the un-slugified branch name" {
    wt new feat/deep/nested

    wt done feat/deep/nested
    [ "$status" -eq 0 ]
    [ ! -d "${REPO}/.worktrees/feat-deep-nested" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# prune
# ──────────────────────────────────────────────────────────────────────────────

@test "worktree prune: removes a worktree whose PR is MERGED" {
    wt new fix/merged
    set_pr_state fix/merged MERGED

    wt prune
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed"* ]]
    [ ! -d "${REPO}/.worktrees/fix-merged" ]
}

@test "worktree prune: removes a worktree whose PR is CLOSED" {
    wt new fix/closed
    set_pr_state fix/closed CLOSED

    wt prune
    [ "$status" -eq 0 ]
    [ ! -d "${REPO}/.worktrees/fix-closed" ]
}

@test "worktree prune: keeps a worktree whose PR is still OPEN" {
    wt new fix/open
    set_pr_state fix/open OPEN

    wt prune
    [ "$status" -eq 0 ]
    [[ "$output" == *"KEEP"* ]]
    [ -d "${REPO}/.worktrees/fix-open" ]
}

@test "worktree prune: keeps a worktree with no PR at all" {
    wt new fix/nopr

    wt prune
    [ "$status" -eq 0 ]
    [[ "$output" == *"PR: none"* ]]
    [ -d "${REPO}/.worktrees/fix-nopr" ]
}

@test "worktree prune: skips a merged worktree that is dirty" {
    wt new fix/dirty
    set_pr_state fix/dirty MERGED
    printf 'dirty\n' > "${REPO}/.worktrees/fix-dirty/scratch.txt"

    wt prune
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
    [[ "$output" == *"worktree is dirty"* ]]
    [ -d "${REPO}/.worktrees/fix-dirty" ]
}

@test "worktree prune: never removes the main checkout" {
    set_pr_state testing MERGED

    wt prune
    [ "$status" -eq 0 ]
    [ -d "${REPO}/.git" ]
    [ -f "${REPO}/.git/HEAD" ]
}

@test "worktree prune: ignores worktrees living outside .worktrees/" {
    git -C "${REPO}" worktree add --quiet -b fix/outside "${TEST_ROOT}/outside" >/dev/null 2>&1
    set_pr_state fix/outside MERGED

    wt prune
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/outside" ]
}

@test "worktree prune: processes several worktrees in one pass" {
    wt new fix/one
    wt new fix/two
    wt new fix/three
    set_pr_state fix/one MERGED
    set_pr_state fix/two OPEN
    set_pr_state fix/three CLOSED

    wt prune
    [ "$status" -eq 0 ]
    [ ! -d "${REPO}/.worktrees/fix-one" ]
    [ -d "${REPO}/.worktrees/fix-two" ]
    [ ! -d "${REPO}/.worktrees/fix-three" ]
}
