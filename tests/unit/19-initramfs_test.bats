#!/usr/bin/env bats
# Unit tests for build_files/base/19-initramfs.sh.
# Run with: bats tests/unit/19-initramfs_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
INITRAMFS_SCRIPT="${SCRIPT_DIR}/../../build_files/base/19-initramfs.sh"

KERNEL_VER="6.12.0-200.fc42.x86_64"
MARKER_PATH="/lib/modules/${KERNEL_VER}/.bluefin-initramfs-done"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/19-initramfs.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    DRACUT_LOG="${TEST_ROOT}/dracut.log"
    RPM_LOG="${TEST_ROOT}/rpm.log"

    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/lib/modules/${KERNEL_VER}"

    export PATH="${STUB_BIN}:${PATH}"
    export DRACUT_LOG RPM_LOG
    unset FORCE_INITRAMFS

    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == *"-qa"* ]]; then
    echo "kernel-6.12.0-200.fc42.x86_64"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm"

    cat > "${STUB_BIN}/dracut" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${DRACUT_LOG}"
prev=""
for arg in "$@"; do
    if [[ "${prev}" == "-f" ]]; then
        touch "${arg}"
    fi
    prev="${arg}"
done
exit 0
EOF
    chmod +x "${STUB_BIN}/dracut"

    # Stub chmod so it doesn't fail on the fake initramfs path
    cat > "${STUB_BIN}/chmod" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/chmod"

    # Rewrite the script to use our test module path prefix and use PATH-based dracut
    PATCHED_SCRIPT="${TEST_ROOT}/19-initramfs-patched.sh"
    sed \
        -e "s|/lib/modules/|${TEST_ROOT}/lib/modules/|g" \
        -e "s|/usr/bin/dracut|dracut|g" \
        "${INITRAMFS_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Normal run (no marker)
# ──────────────────────────────────────────────────────────────────────────────

@test "19-initramfs: runs dracut when no marker exists" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${DRACUT_LOG}" ]
    grep -q "ostree" "${DRACUT_LOG}"
}

@test "19-initramfs: writes marker after successful dracut" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}${MARKER_PATH}" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Skip when marker present
# ──────────────────────────────────────────────────────────────────────────────

@test "19-initramfs: skips dracut when marker already exists" {
    touch "${TEST_ROOT}${MARKER_PATH}"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -f "${DRACUT_LOG}" ]
    [[ "$output" == *"skipping dracut"* ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# FORCE_INITRAMFS override
# ──────────────────────────────────────────────────────────────────────────────

@test "19-initramfs: FORCE_INITRAMFS=1 runs dracut even when marker exists" {
    touch "${TEST_ROOT}${MARKER_PATH}"
    export FORCE_INITRAMFS=1
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${DRACUT_LOG}" ]
    grep -q "ostree" "${DRACUT_LOG}"
}

@test "19-initramfs: FORCE_INITRAMFS=0 respects marker and skips dracut" {
    touch "${TEST_ROOT}${MARKER_PATH}"
    export FORCE_INITRAMFS=0
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -f "${DRACUT_LOG}" ]
}

@test "19-initramfs: dracut called with --reproducible and --add ostree flags" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "\-\-reproducible" "${DRACUT_LOG}"
    grep -q "\-\-add ostree" "${DRACUT_LOG}"
}
