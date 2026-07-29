#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/11-framework-ucsi-workaround.sh
# Run with: bats tests/unit/11-framework-ucsi-workaround_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../../system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/11-framework-ucsi-workaround.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/11-framework-ucsi-workaround.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"

    cat > "${STUB_BIN}/rpm-ostree" <<EOF
#!/usr/bin/bash
echo "rpm-ostree \$*" >> "${STUB_BIN}/rpm-ostree.log"
if [[ "\$1" == "kargs" && "\$#" -eq 1 ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm-ostree"

    PATCHED_SCRIPT="${TEST_ROOT}/11-framework-ucsi-workaround-patched.sh"
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

@test "11-framework-ucsi-workaround: non-Framework systems are skipped" {
    echo "ACME Corp" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (Intel Core Ultra Series 1)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [ ! -f "${STUB_BIN}/rpm-ostree.log" ]
}

@test "11-framework-ucsi-workaround: Framework Core Ultra systems append autosuspend karg" {
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (Intel Core Ultra Series 1)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    grep -q "kargs --append-if-missing=usbcore.autosuspend=-1" "${STUB_BIN}/rpm-ostree.log"
    [[ "$output" == *"Applied Framework UCSI workaround"* ]]
}

@test "11-framework-ucsi-workaround: existing autosuspend karg is not appended again" {
    cat > "${STUB_BIN}/rpm-ostree" <<EOF
#!/usr/bin/bash
echo "rpm-ostree \$*" >> "${STUB_BIN}/rpm-ostree.log"
if [[ "\$1" == "kargs" && "\$#" -eq 1 ]]; then
    echo "quiet usbcore.autosuspend=-1"
    exit 0
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm-ostree"
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (Intel Core Ultra Series 1)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured"* ]]
    ! grep -q -- "--append-if-missing" "${STUB_BIN}/rpm-ostree.log"
}

@test "11-framework-ucsi-workaround: missing rpm-ostree exits with warning" {
    rm -f "${STUB_BIN}/rpm-ostree"
    export PATH="${STUB_BIN}:/usr/bin:/bin"
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (Intel Core Ultra Series 1)" > "${TEST_ROOT}/product_name"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: rpm-ostree not found"* ]]
}
