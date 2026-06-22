#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/share/ublue-os/user-setup.hooks.d/20-framework.sh
# Run with: bats tests/unit/20-framework_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../../system_files/shared/usr/share/ublue-os/user-setup.hooks.d/20-framework.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/20-framework.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/linuxbrew"
    export PATH="${STUB_BIN}:${PATH}"

    # Stub brew — log calls, report packages as not installed
    cat > "${STUB_BIN}/brew" <<EOF
#!/usr/bin/bash
echo "brew \$*" >> "${STUB_BIN}/brew.log"
# 'list --cask' returns 1 (not installed) so install path is exercised
[[ "\$1" == "list" ]] && exit 1
exit 0
EOF
    chmod +x "${STUB_BIN}/brew"

    # Patch: stub libsetup.sh, redirect chassis_vendor, and make BREW_PREFIX writable
    PATCHED_SCRIPT="${TEST_ROOT}/20-framework-patched.sh"
    sed \
        -e "s|source /usr/lib/ublue/setup-services/libsetup.sh|version-script() { return 0; }|g" \
        -e "s|/sys/devices/virtual/dmi/id/chassis_vendor|${TEST_ROOT}/chassis_vendor|g" \
        -e "s|BREW_PREFIX=\"/home/linuxbrew/\.linuxbrew\"|BREW_PREFIX=\"${TEST_ROOT}/linuxbrew\"|g" \
        "${HOOK_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT TEST_ROOT STUB_BIN
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "20-framework: brew never called for non-Framework vendor" {
    echo "ACME Corp" > "${TEST_ROOT}/chassis_vendor"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -f "${STUB_BIN}/brew.log" ]
}

@test "20-framework: brew install called when vendor is Framework" {
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "install" "${STUB_BIN}/brew.log"
}

@test "20-framework: missing brew exits cleanly" {
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    rm -f "${STUB_BIN}/brew"
    export PATH="${STUB_BIN}:/usr/bin:/bin"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: brew not found"* ]]
}

@test "20-framework: non-writable brew prefix skips install with warning" {
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    chmod 555 "${TEST_ROOT}/linuxbrew"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"user lacks write permission"* ]]
    [ ! -f "${STUB_BIN}/brew.log" ]
}

@test "20-framework: installed casks are skipped without install calls" {
    cat > "${STUB_BIN}/brew" <<EOF
#!/usr/bin/bash
echo "brew \$*" >> "${STUB_BIN}/brew.log"
[[ "\$1" == "list" ]] && exit 0
exit 0
EOF
    chmod +x "${STUB_BIN}/brew"
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed, skipping"* ]]
    ! grep -q "install" "${STUB_BIN}/brew.log"
}
