#!/usr/bin/env bats
# Unit tests for build_files/shared/disable-repos.sh.
# Run with: bats tests/unit/disable-repos_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
DISABLE_REPOS_LIB="${SCRIPT_DIR}/../../build_files/shared/disable-repos.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/disable-repos.${BATS_TEST_NUMBER:-0}.$$"
    mkdir -p "${TEST_ROOT}"
    export REPOS_DIR="${TEST_ROOT}"

    # shellcheck source=../../build_files/shared/disable-repos.sh
    source "${DISABLE_REPOS_LIB}"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# Helper: create a .repo file with enabled=1
make_repo_enabled() {
    local name="$1"
    printf '[%s]\nenabled=1\n' "$name" > "${REPOS_DIR}/${name}.repo"
}

# Helper: assert a .repo file now has enabled=0 (not enabled=1)
assert_disabled() {
    local name="$1"
    local content
    content="$(cat "${REPOS_DIR}/${name}.repo")"
    [[ "$content" != *"enabled=1"* ]] || {
        echo "FAIL: ${name}.repo still contains enabled=1"
        return 1
    }
    [[ "$content" == *"enabled=0"* ]] || {
        echo "FAIL: ${name}.repo does not contain enabled=0"
        return 1
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Named repos
# ──────────────────────────────────────────────────────────────────────────────

@test "disable_third_party_repos: disables fedora-multimedia" {
    make_repo_enabled "fedora-multimedia"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    assert_disabled "fedora-multimedia"
}

@test "disable_third_party_repos: disables tailscale" {
    make_repo_enabled "tailscale"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    assert_disabled "tailscale"
}

@test "disable_third_party_repos: disables fedora-cisco-openh264" {
    make_repo_enabled "fedora-cisco-openh264"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    assert_disabled "fedora-cisco-openh264"
}

@test "disable_third_party_repos: skips missing named repo without error" {
    # No tailscale.repo present — should still succeed
    run disable_third_party_repos
    [ "$status" -eq 0 ]
}

# ──────────────────────────────────────────────────────────────────────────────
# COPR repos
# ──────────────────────────────────────────────────────────────────────────────

@test "disable_third_party_repos: disables a COPR repo" {
    printf '[copr:atim:starship]\nenabled=1\n' > "${REPOS_DIR}/_copr:atim:starship.repo"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    local content
    content="$(cat "${REPOS_DIR}/_copr:atim:starship.repo")"
    [[ "$content" != *"enabled=1"* ]]
    [[ "$content" == *"enabled=0"* ]]
}

@test "disable_third_party_repos: disables multiple COPR repos" {
    printf '[copr:atim:starship]\nenabled=1\n' > "${REPOS_DIR}/_copr:atim:starship.repo"
    printf '[copr:user:pkg]\nenabled=1\n' > "${REPOS_DIR}/_copr:user:pkg.repo"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    grep -q "enabled=0" "${REPOS_DIR}/_copr:atim:starship.repo"
    grep -q "enabled=0" "${REPOS_DIR}/_copr:user:pkg.repo"
}

# ──────────────────────────────────────────────────────────────────────────────
# RPM Fusion repos
# ──────────────────────────────────────────────────────────────────────────────

@test "disable_third_party_repos: disables rpmfusion-free" {
    make_repo_enabled "rpmfusion-free"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    assert_disabled "rpmfusion-free"
}

@test "disable_third_party_repos: disables rpmfusion-nonfree" {
    make_repo_enabled "rpmfusion-nonfree"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    assert_disabled "rpmfusion-nonfree"
}

@test "disable_third_party_repos: disables multiple rpmfusion repos at once" {
    make_repo_enabled "rpmfusion-free"
    make_repo_enabled "rpmfusion-nonfree"
    make_repo_enabled "rpmfusion-free-updates"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    assert_disabled "rpmfusion-free"
    assert_disabled "rpmfusion-nonfree"
    assert_disabled "rpmfusion-free-updates"
}

# ──────────────────────────────────────────────────────────────────────────────
# CoreOS pool
# ──────────────────────────────────────────────────────────────────────────────

@test "disable_third_party_repos: disables fedora-coreos-pool when present" {
    make_repo_enabled "fedora-coreos-pool"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    assert_disabled "fedora-coreos-pool"
}

@test "disable_third_party_repos: succeeds when fedora-coreos-pool is absent" {
    run disable_third_party_repos
    [ "$status" -eq 0 ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Idempotency
# ──────────────────────────────────────────────────────────────────────────────

@test "disable_third_party_repos: already-disabled repo is unchanged (idempotent)" {
    printf '[tailscale]\nenabled=0\n' > "${REPOS_DIR}/tailscale.repo"
    run disable_third_party_repos
    [ "$status" -eq 0 ]
    grep -q "enabled=0" "${REPOS_DIR}/tailscale.repo"
    ! grep -q "enabled=1" "${REPOS_DIR}/tailscale.repo"
}

# ──────────────────────────────────────────────────────────────────────────────
# All repos together
# ──────────────────────────────────────────────────────────────────────────────

@test "disable_third_party_repos: disables all repo types in one call" {
    make_repo_enabled "fedora-multimedia"
    make_repo_enabled "tailscale"
    make_repo_enabled "fedora-cisco-openh264"
    make_repo_enabled "rpmfusion-free"
    make_repo_enabled "rpmfusion-nonfree"
    make_repo_enabled "fedora-coreos-pool"
    printf '[copr:user:pkg]\nenabled=1\n' > "${REPOS_DIR}/_copr:user:pkg.repo"

    run disable_third_party_repos
    [ "$status" -eq 0 ]

    assert_disabled "fedora-multimedia"
    assert_disabled "tailscale"
    assert_disabled "fedora-cisco-openh264"
    assert_disabled "rpmfusion-free"
    assert_disabled "rpmfusion-nonfree"
    assert_disabled "fedora-coreos-pool"
    grep -q "enabled=0" "${REPOS_DIR}/_copr:user:pkg.repo"
}
