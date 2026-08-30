#!/usr/bin/env bats
# Unit tests for .github/scripts/install-hooks.sh.
# Run with: bats tests/unit/install-hooks_test.bats
#
# The script is exercised against a throwaway git repository so the real
# checkout, the developer's global git config and $HOME are never touched.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
INSTALL_HOOKS="${SCRIPT_DIR}/../../.github/scripts/install-hooks.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/install-hooks.${BATS_TEST_NUMBER:-0}.$$"
    REPO="${TEST_ROOT}/repo"
    GLOBAL_HOOKS="${TEST_ROOT}/global-hooks"

    mkdir -p "${REPO}" "${GLOBAL_HOOKS}"

    # Isolate every git config layer: a real ~/.gitconfig with core.hooksPath
    # would otherwise change which branch of the script runs.
    export HOME="${TEST_ROOT}"
    export GIT_CONFIG_GLOBAL="${TEST_ROOT}/gitconfig-global"
    export GIT_CONFIG_SYSTEM="${TEST_ROOT}/gitconfig-system"
    export GIT_CONFIG_NOSYSTEM=1
    : > "${GIT_CONFIG_GLOBAL}"
    : > "${GIT_CONFIG_SYSTEM}"

    git -C "${REPO}" init --quiet --initial-branch=testing
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "Test"
    git -C "${REPO}" commit --quiet --allow-empty -m "root"

    HOOKS_DIR="${REPO}/.git/hooks"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# Run install-hooks.sh from inside the sandbox repository.
run_install() {
    run bash -c "cd '${REPO}' && bash '${INSTALL_HOOKS}' 2>&1"
}

# Run the generated pre-push hook with the given argv, from inside the repo.
run_hook() {
    local dir="${1}"
    shift
    run bash -c "cd '${dir}' && bash '${HOOKS_DIR}/pre-push' $*"
}

set_global_hooks_path() {
    git config --file "${GIT_CONFIG_GLOBAL}" core.hooksPath "${GLOBAL_HOOKS}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Installation
# ──────────────────────────────────────────────────────────────────────────────

@test "install-hooks: installs an executable pre-push hook" {
    run_install
    [ "$status" -eq 0 ]
    [ -x "${HOOKS_DIR}/pre-push" ]
    [[ "$output" == *"Installed pre-push hook"* ]]
}

@test "install-hooks: leaves core.hooksPath unset when no hooksPath is configured" {
    run_install
    [ "$status" -eq 0 ]

    run git -C "${REPO}" config --local --get core.hooksPath
    [ "$status" -ne 0 ]

    run git -C "${REPO}" config --local --get bluefin.chainedHooksPath
    [ "$status" -ne 0 ]
}

@test "install-hooks: is idempotent — a second run still installs the hook" {
    run_install
    [ "$status" -eq 0 ]
    run_install
    [ "$status" -eq 0 ]
    [ -x "${HOOKS_DIR}/pre-push" ]
}

@test "install-hooks: installs into the common git dir when run from a linked worktree" {
    git -C "${REPO}" worktree add --quiet -b feat/wt "${TEST_ROOT}/wt" >/dev/null 2>&1

    run bash -c "cd '${TEST_ROOT}/wt' && bash '${INSTALL_HOOKS}' 2>&1"
    [ "$status" -eq 0 ]

    # The hook belongs to the shared hooks dir, not the per-worktree git dir.
    [ -x "${HOOKS_DIR}/pre-push" ]
    [ ! -e "${REPO}/.git/worktrees/wt/hooks/pre-push" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# core.hooksPath chaining
# ──────────────────────────────────────────────────────────────────────────────

@test "install-hooks: redirects core.hooksPath and records the chained path" {
    set_global_hooks_path
    run_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"core.hooksPath was set to"* ]]

    run git -C "${REPO}" config --local --get core.hooksPath
    [ "$status" -eq 0 ]
    [ "$output" = "${HOOKS_DIR}" ]

    run git -C "${REPO}" config --local --get bluefin.chainedHooksPath
    [ "$status" -eq 0 ]
    [ "$output" = "${GLOBAL_HOOKS}" ]
}

@test "install-hooks: appends a chain stanza to pre-push when hooksPath was redirected" {
    set_global_hooks_path
    run_install
    [ "$status" -eq 0 ]

    run grep -F "${GLOBAL_HOOKS}/pre-push" "${HOOKS_DIR}/pre-push"
    [ "$status" -eq 0 ]
}

@test "install-hooks: re-run keeps the chained hooks path instead of losing it" {
    set_global_hooks_path
    run_install
    [ "$status" -eq 0 ]

    # On the second run core.hooksPath already points at HOOKS_DIR, so the
    # original target can only come from bluefin.chainedHooksPath.
    run_install
    [ "$status" -eq 0 ]

    run git -C "${REPO}" config --local --get bluefin.chainedHooksPath
    [ "$status" -eq 0 ]
    [ "$output" = "${GLOBAL_HOOKS}" ]

    run grep -F "${GLOBAL_HOOKS}/pre-push" "${HOOKS_DIR}/pre-push"
    [ "$status" -eq 0 ]
}

@test "install-hooks: does not chain when core.hooksPath already equals the hooks dir" {
    git config --file "${GIT_CONFIG_GLOBAL}" core.hooksPath "${HOOKS_DIR}"
    run_install
    [ "$status" -eq 0 ]
    [[ "$output" != *"core.hooksPath was set to"* ]]
}

@test "install-hooks: chained pre-push runs after the guards pass" {
    set_global_hooks_path
    cat > "${GLOBAL_HOOKS}/pre-push" <<EOF
#!/usr/bin/env bash
echo "chained-ran:\$1"
EOF
    chmod +x "${GLOBAL_HOOKS}/pre-push"

    run_install
    [ "$status" -eq 0 ]

    git -C "${REPO}" checkout --quiet -b testing 2>/dev/null || git -C "${REPO}" checkout --quiet testing
    run_hook "${REPO}" projectbluefin "git@github.com:projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chained-ran:projectbluefin"* ]]
}

@test "install-hooks: chained pre-push that is not executable warns instead of failing" {
    set_global_hooks_path
    printf '#!/usr/bin/env bash\necho nope\n' > "${GLOBAL_HOOKS}/pre-push"
    chmod -x "${GLOBAL_HOOKS}/pre-push"

    run_install
    [ "$status" -eq 0 ]

    run_hook "${REPO}" projectbluefin "https://github.com/projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not executable"* ]]
    [[ "$output" != *"nope"* ]]
}

@test "install-hooks: shims other global hooks back to the chained directory" {
    set_global_hooks_path
    cat > "${GLOBAL_HOOKS}/commit-msg" <<'EOF'
#!/usr/bin/env bash
echo "global-commit-msg:$1"
EOF
    chmod +x "${GLOBAL_HOOKS}/commit-msg"

    run_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chained global hook: commit-msg"* ]]
    [ -x "${HOOKS_DIR}/commit-msg" ]

    run bash "${HOOKS_DIR}/commit-msg" MSGFILE
    [ "$status" -eq 0 ]
    [ "$output" = "global-commit-msg:MSGFILE" ]
}

@test "install-hooks: shim exits 0 when the chained hook is missing or not executable" {
    set_global_hooks_path
    printf '#!/usr/bin/env bash\necho should-not-run\n' > "${GLOBAL_HOOKS}/commit-msg"
    chmod -x "${GLOBAL_HOOKS}/commit-msg"

    run_install
    [ "$status" -eq 0 ]

    run bash "${HOOKS_DIR}/commit-msg"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "install-hooks: does not shim .sample hooks or overwrite pre-push" {
    set_global_hooks_path
    printf '#!/usr/bin/env bash\ntrue\n' > "${GLOBAL_HOOKS}/pre-commit.sample"
    printf '#!/usr/bin/env bash\necho global-pre-push\n' > "${GLOBAL_HOOKS}/pre-push"
    chmod +x "${GLOBAL_HOOKS}/pre-commit.sample" "${GLOBAL_HOOKS}/pre-push"

    run_install
    [ "$status" -eq 0 ]
    [[ "$output" != *"Chained global hook: pre-commit.sample"* ]]

    # git init ships its own .sample files here; none of them may be replaced
    # by a passthrough shim.
    run grep -F "Passthrough shim" "${HOOKS_DIR}/pre-commit.sample"
    [ "$status" -ne 0 ]

    # pre-push is the script's own hook, not a passthrough shim.
    run grep -F "Refusing to push" "${HOOKS_DIR}/pre-push"
    [ "$status" -eq 0 ]
}

@test "install-hooks: skips directories found in the chained hooks directory" {
    set_global_hooks_path
    mkdir -p "${GLOBAL_HOOKS}/subdir"

    run_install
    [ "$status" -eq 0 ]
    [ ! -e "${HOOKS_DIR}/subdir" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Generated pre-push hook — guard 1: remote org
# ──────────────────────────────────────────────────────────────────────────────

@test "pre-push: rejects a push to a remote outside the projectbluefin org" {
    run_install
    run_hook "${REPO}" fork "git@github.com:someone/bluefin.git"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Only repositories in the projectbluefin org accept writes."* ]]
}

@test "pre-push: allows an ssh projectbluefin remote url" {
    run_install
    run_hook "${REPO}" projectbluefin "git@github.com:projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
}

@test "pre-push: allows an https projectbluefin remote url" {
    run_install
    run_hook "${REPO}" origin "https://github.com/projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
}

@test "pre-push: SKIP_REMOTE_GUARD bypasses the org check" {
    run_install
    run bash -c "cd '${REPO}' && SKIP_REMOTE_GUARD=1 SKIP_WORKTREE_GUARD=1 bash '${HOOKS_DIR}/pre-push' fork 'git@github.com:someone/bluefin.git'"
    [ "$status" -eq 0 ]
}

@test "pre-push: resolves the remote url from the remote name when argv omits it" {
    git -C "${REPO}" remote add fork "git@github.com:someone/bluefin.git"
    run_install
    run_hook "${REPO}" fork
    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to push to 'fork'"* ]]
}

@test "pre-push: allows the push when no remote url can be resolved" {
    run_install
    run_hook "${REPO}" no-such-remote
    [ "$status" -eq 0 ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Generated pre-push hook — guard 2: main checkout hygiene
# ──────────────────────────────────────────────────────────────────────────────

@test "pre-push: rejects a feature branch pushed from the main checkout" {
    git -C "${REPO}" checkout --quiet -b fix/thing
    run_install
    run_hook "${REPO}" projectbluefin "git@github.com:projectbluefin/bluefin.git"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to push feature branch 'fix/thing' from the main checkout."* ]]
    [[ "$output" == *"worktree.sh new fix/thing"* ]]
}

@test "pre-push: allows testing from the main checkout" {
    git -C "${REPO}" checkout --quiet testing
    run_install
    run_hook "${REPO}" projectbluefin "git@github.com:projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
}

@test "pre-push: allows main from the main checkout" {
    git -C "${REPO}" checkout --quiet -b main
    run_install
    run_hook "${REPO}" projectbluefin "git@github.com:projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
}

@test "pre-push: allows a feature branch pushed from a linked worktree" {
    run_install
    git -C "${REPO}" worktree add --quiet -b fix/thing "${TEST_ROOT}/wt" >/dev/null 2>&1

    run_hook "${TEST_ROOT}/wt" projectbluefin "git@github.com:projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
}

@test "pre-push: SKIP_WORKTREE_GUARD bypasses the main-checkout check" {
    git -C "${REPO}" checkout --quiet -b fix/thing
    run_install
    run bash -c "cd '${REPO}' && SKIP_WORKTREE_GUARD=1 bash '${HOOKS_DIR}/pre-push' projectbluefin 'git@github.com:projectbluefin/bluefin.git'"
    [ "$status" -eq 0 ]
}

@test "pre-push: allows a detached HEAD in the main checkout" {
    run_install
    git -C "${REPO}" checkout --quiet --detach HEAD
    run_hook "${REPO}" projectbluefin "git@github.com:projectbluefin/bluefin.git"
    [ "$status" -eq 0 ]
}
