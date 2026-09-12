#!/usr/bin/env bats
# Unit tests for build_files/shared/build.sh
# Run with: bats tests/unit/build_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SCRIPT="${REPO_ROOT}/build_files/shared/build.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/build.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    STAGE_LOG="${TEST_ROOT}/stage.log"
    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/ctx/system_files/shared"
    mkdir -p "${TEST_ROOT}/ctx/build_files/shared/utils"
    touch "${TEST_ROOT}/ctx/build_files/shared/utils/ghcurl"

    ORIG_PATH="${PATH}"
    export PATH="${STUB_BIN}:${PATH}"
    export STAGE_LOG

    # Stub commands used in build.sh
    cat > "${STUB_BIN}/dnf5" << 'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/dnf5"

    cat > "${STUB_BIN}/rpm" << 'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm"

    cat > "${STUB_BIN}/rsync" << 'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/rsync"

    cat > "${STUB_BIN}/install" << 'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/install"

    # Create mock stage scripts that log their invocation
    MOCK_STAGES=(
        "base/00-image-info.sh"
        "base/03-packages.sh"
        "base/04-install-kernel-akmods.sh"
        "base/05-override-install.sh"
        "shared/build-gnome-extensions.sh"
        "base/17-cleanup.sh"
        "base/18-workarounds.sh"
        "base/19-initramfs.sh"
        "shared/validate-repos.sh"
        "shared/clean-stage.sh"
        "base/20-tests.sh"
    )

    for stage in "${MOCK_STAGES[@]}"; do
        stage_path="${TEST_ROOT}/ctx/build_files/${stage}"
        mkdir -p "$(dirname "${stage_path}")"
        cat > "${stage_path}" << EOF
#!/usr/bin/bash
echo "${stage}" >> "${STAGE_LOG}"
if [[ -n "\${FAIL_STAGE:-}" && "\${FAIL_STAGE}" == "${stage}" ]]; then
    exit 1
fi
exit 0
EOF
        chmod +x "${stage_path}"
    done

    # Prepare patched build.sh pointing /ctx to TEST_ROOT/ctx and /tmp to TEST_ROOT/tmp
    PATCHED_SCRIPT="${TEST_ROOT}/build-patched.sh"
    sed -e "s|/ctx|${TEST_ROOT}/ctx|g"         -e "s|/tmp|${TEST_ROOT}/tmp|g"         "${BUILD_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
}

teardown() {
    export PATH="${ORIG_PATH}"
    rm -rf "${TEST_ROOT}"
}

@test "build.sh: executes build stages in exact expected sequence" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]

    # Verify every stage ran in exact order
    run cat "${STAGE_LOG}"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "base/00-image-info.sh" ]
    [ "${lines[1]}" = "base/03-packages.sh" ]
    [ "${lines[2]}" = "base/04-install-kernel-akmods.sh" ]
    [ "${lines[3]}" = "base/05-override-install.sh" ]
    [ "${lines[4]}" = "shared/build-gnome-extensions.sh" ]
    [ "${lines[5]}" = "base/17-cleanup.sh" ]
    [ "${lines[6]}" = "base/18-workarounds.sh" ]
    [ "${lines[7]}" = "base/19-initramfs.sh" ]
    [ "${lines[8]}" = "shared/validate-repos.sh" ]
    [ "${lines[9]}" = "shared/clean-stage.sh" ]
    [ "${lines[10]}" = "base/20-tests.sh" ]
}

@test "build.sh: fails immediately if a stage fails" {
    export FAIL_STAGE="base/05-override-install.sh"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -ne 0 ]

    # Subsequent stages should not have run
    run cat "${STAGE_LOG}"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "base/05-override-install.sh" ]
    [[ "${output}" != *"base/17-cleanup.sh"* ]]
}

@test "build.sh: fails immediately if dnf5 config-manager fails" {
    cat > "${STUB_BIN}/dnf5" << 'EOF'
#!/usr/bin/bash
exit 2
EOF
    chmod +x "${STUB_BIN}/dnf5"

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -ne 0 ]
    [ ! -f "${STAGE_LOG}" ]
}
