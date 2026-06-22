#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/share/ublue-os/user-setup.hooks.d/99-privileged.sh
# Run with: bats tests/unit/99-privileged_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../../system_files/shared/usr/share/ublue-os/user-setup.hooks.d/99-privileged.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/99-privileged.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"

    # Stub pkexec — log its arguments
    cat > "${STUB_BIN}/pkexec" <<EOF
#!/usr/bin/bash
echo "pkexec \$*" >> "${STUB_BIN}/pkexec.log"
exit 0
EOF
    chmod +x "${STUB_BIN}/pkexec"
    export TEST_ROOT STUB_BIN
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "99-privileged: pkexec called with /usr/bin/ublue-privileged-setup" {
    run bash "${HOOK_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "/usr/bin/ublue-privileged-setup" "${STUB_BIN}/pkexec.log"
}

@test "99-privileged: pkexec failure exits non-zero" {
    cat > "${STUB_BIN}/pkexec" <<EOF
#!/usr/bin/bash
exit 23
EOF
    chmod +x "${STUB_BIN}/pkexec"

    run bash "${HOOK_SCRIPT}"

    [ "$status" -eq 23 ]
}
