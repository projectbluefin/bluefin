#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/12-framework-amd-kargs-cleanup.sh
# Run with: bats tests/unit/12-framework-amd-kargs-cleanup_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../../system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/12-framework-amd-kargs-cleanup.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/12-framework-amd-kargs-cleanup.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"

    # Default rpm-ostree stub: kargs returns no blacklist entry, deletes log calls
    cat > "${STUB_BIN}/rpm-ostree" <<'EOF'
#!/usr/bin/bash
echo "rpm-ostree $*" >> "${STUB_BIN}/rpm-ostree.log"
if [[ "$1" == "kargs" && "$#" -eq 1 ]]; then
    echo "quiet rhgb"
    exit 0
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm-ostree"

    PATCHED_SCRIPT="${TEST_ROOT}/12-framework-amd-kargs-cleanup-patched.sh"
    sed \
        -e "s|source /usr/lib/ublue/setup-services/libsetup.sh|version-script() { return 0; }|g" \
        -e "s|/sys/devices/virtual/dmi/id/chassis_vendor|${TEST_ROOT}/chassis_vendor|g" \
        -e "s|/sys/devices/virtual/dmi/id/product_name|${TEST_ROOT}/product_name|g" \
        "${HOOK_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT TEST_ROOT STUB_BIN
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "12-framework-amd-kargs-cleanup: non-Framework systems are skipped" {
    echo "ACME Corp" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (AMD Ryzen 7040 Series)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [ ! -f "${STUB_BIN}/rpm-ostree.log" ]
}

@test "12-framework-amd-kargs-cleanup: Intel Framework systems are skipped" {
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (Intel Core Ultra Series 1)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [ ! -f "${STUB_BIN}/rpm-ostree.log" ]
}

@test "12-framework-amd-kargs-cleanup: unknown Framework product is skipped" {
    # Positive AMD match: a future Framework SKU with no AMD in the name must not
    # have its boot config mutated.
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 15 (RISC-V Edition)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [ ! -f "${STUB_BIN}/rpm-ostree.log" ]
}

@test "12-framework-amd-kargs-cleanup: AMD Framework without stale karg exits cleanly" {
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (AMD Ryzen 7040 Series)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to do"* ]]
    ! grep -q -- "--delete" "${STUB_BIN}/rpm-ostree.log" 2>/dev/null
}

@test "12-framework-amd-kargs-cleanup: AMD Framework with stale karg deletes it" {
    # Stub: kargs output includes the stale blacklist entry
    cat > "${STUB_BIN}/rpm-ostree" <<'EOF'
#!/usr/bin/bash
echo "rpm-ostree $*" >> "${STUB_BIN}/rpm-ostree.log"
if [[ "$1" == "kargs" && "$#" -eq 1 ]]; then
    echo "quiet rhgb module_blacklist=hid_sensor_hub"
    exit 0
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm-ostree"

    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 16 (AMD Ryzen 7040 Series)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    grep -q "kargs --delete=module_blacklist=hid_sensor_hub" "${STUB_BIN}/rpm-ostree.log"
    [[ "$output" == *"Removed stale AMD Framework karg"* ]]
}

@test "12-framework-amd-kargs-cleanup: AMD Ryzen AI product name is matched" {
    cat > "${STUB_BIN}/rpm-ostree" <<'EOF'
#!/usr/bin/bash
echo "rpm-ostree $*" >> "${STUB_BIN}/rpm-ostree.log"
if [[ "$1" == "kargs" && "$#" -eq 1 ]]; then
    echo "quiet rhgb module_blacklist=hid_sensor_hub"
    exit 0
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm-ostree"

    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (AMD Ryzen AI 300 Series)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    grep -q "kargs --delete=module_blacklist=hid_sensor_hub" "${STUB_BIN}/rpm-ostree.log"
}

@test "12-framework-amd-kargs-cleanup: missing rpm-ostree exits with warning" {
    rm -f "${STUB_BIN}/rpm-ostree"
    export PATH="${STUB_BIN}:/usr/bin:/bin"

    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (AMD Ryzen 7040 Series)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: rpm-ostree not found"* ]]
}

@test "12-framework-amd-kargs-cleanup: missing DMI info exits cleanly" {
    # Neither chassis_vendor nor product_name file exists

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DMI information not available"* ]]
}
