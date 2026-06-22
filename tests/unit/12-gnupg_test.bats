#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/share/ublue-os/user-setup.hooks.d/12-gnupg.sh
# Run with: bats tests/unit/12-gnupg_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../../system_files/shared/usr/share/ublue-os/user-setup.hooks.d/12-gnupg.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/12-gnupg.${BATS_TEST_NUMBER:-0}.$$"
    mkdir -p "${TEST_ROOT}/usr/libexec"
    mkdir -p "${TEST_ROOT}/home/.gnupg"
    export HOME="${TEST_ROOT}/home"

    # Patch /usr/libexec/scdaemon -> TEST_ROOT path
    PATCHED_SCRIPT="${TEST_ROOT}/12-gnupg-patched.sh"
    sed \
        -e "s|/usr/libexec/scdaemon|${TEST_ROOT}/usr/libexec/scdaemon|g" \
        "${HOOK_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT TEST_ROOT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "12-gnupg: scdaemon-program line added to gpg-agent.conf when scdaemon exists" {
    touch "${TEST_ROOT}/usr/libexec/scdaemon"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "scdaemon-program" "${HOME}/.gnupg/gpg-agent.conf"
}

@test "12-gnupg: scdaemon-program not duplicated when already in conf" {
    touch "${TEST_ROOT}/usr/libexec/scdaemon"
    echo "scdaemon-program /usr/libexec/scdaemon" > "${HOME}/.gnupg/gpg-agent.conf"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ "$(grep -c "scdaemon-program" "${HOME}/.gnupg/gpg-agent.conf")" -eq 1 ]
}

@test "12-gnupg: conf not touched when scdaemon absent" {
    # scdaemon not present — conf should not be created
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -f "${HOME}/.gnupg/gpg-agent.conf" ]
}

@test "12-gnupg: creates .gnupg with mode 700" {
    rm -rf "${HOME}/.gnupg"
    touch "${TEST_ROOT}/usr/libexec/scdaemon"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [ -d "${HOME}/.gnupg" ]
    [ "$(stat -c '%a' "${HOME}/.gnupg")" = "700" ]
}

@test "12-gnupg: running twice does not duplicate scdaemon-program line" {
    touch "${TEST_ROOT}/usr/libexec/scdaemon"

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^scdaemon-program ' "${HOME}/.gnupg/gpg-agent.conf")" -eq 1 ]
}
