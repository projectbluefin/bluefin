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
        -e "s|/var/lib/ublue-os/.framework-ucsi-workaround-v1|${TEST_ROOT}/framework-ucsi-workaround-v1|g" \
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
    [ -f "${TEST_ROOT}/framework-ucsi-workaround-v1" ]
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
    [ -f "${TEST_ROOT}/framework-ucsi-workaround-v1" ]
}

@test "11-framework-ucsi-workaround: missing rpm-ostree exits with warning" {
    rm -f "${STUB_BIN}/rpm-ostree"
    # Drop the stub so the hook's `command -v rpm-ostree` guard is exercised for
    # real. PATH is narrowed for the hook process ONLY — it must not re-admit
    # the host's /usr/bin. On any rpm-ostree host (Bluefin and every other
    # ostree desktop this project is developed on) the real binary would be
    # found there, the warning branch would never run, and the hook would go on
    # to drive rpm-ostree against the developer's own deployment. Setting PATH
    # via `env` rather than `export` keeps the change off the test's own shell,
    # so teardown still has its normal PATH.
    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (Intel Core Ultra Series 1)" > "${TEST_ROOT}/product_name"

    run env PATH="${STUB_BIN}" "${BASH}" "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: rpm-ostree not found"* ]]
    # bluefin#1126: an attempt that never reached rpm-ostree must not be
    # recorded as done, or the affected laptop never gets the workaround.
    [ ! -f "${TEST_ROOT}/framework-ucsi-workaround-v1" ]
}

@test "11-framework-ucsi-workaround: missing DMI info is not marked complete" {
    # Neither chassis_vendor nor product_name file exists

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DMI information not available"* ]]
    [ ! -f "${TEST_ROOT}/framework-ucsi-workaround-v1" ]
}

@test "11-framework-ucsi-workaround: failed karg append is not marked complete and retries" {
    # Stub: appending the karg fails (e.g. rpm-ostree busy with another
    # transaction). bluefin#1126: a failed application must not be recorded as
    # done, so a later boot retries it.
    cat > "${STUB_BIN}/rpm-ostree" <<EOF
#!/usr/bin/bash
echo "rpm-ostree \$*" >> "${STUB_BIN}/rpm-ostree.log"
if [[ "\$1" == "kargs" && "\$#" -eq 1 ]]; then
    echo "quiet rhgb"
    exit 0
fi
if [[ "\$1" == "kargs" && "\$2" == --append-if-missing=* ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm-ostree"

    echo "Framework" > "${TEST_ROOT}/chassis_vendor"
    echo "Laptop 13 (Intel Core Ultra Series 1)" > "${TEST_ROOT}/product_name"

    # First (failing) invocation
    run bash "${PATCHED_SCRIPT}"

    [ "$status" -ne 0 ]
    [[ "$output" == *"will retry on next boot"* ]]
    [ ! -f "${TEST_ROOT}/framework-ucsi-workaround-v1" ]

    # Second invocation with a working rpm-ostree simulates a later boot retry
    cat > "${STUB_BIN}/rpm-ostree" <<EOF
#!/usr/bin/bash
echo "rpm-ostree \$*" >> "${STUB_BIN}/rpm-ostree.log"
if [[ "\$1" == "kargs" && "\$#" -eq 1 ]]; then
    echo "quiet rhgb"
    exit 0
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm-ostree"

    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Applied Framework UCSI workaround"* ]]
    [ -f "${TEST_ROOT}/framework-ucsi-workaround-v1" ]
    grep -q "kargs --append-if-missing=usbcore.autosuspend=-1" "${STUB_BIN}/rpm-ostree.log"
}

@test "11-framework-ucsi-workaround: already-marked complete skips without checking hardware" {
    mkdir -p "$(dirname "${TEST_ROOT}/framework-ucsi-workaround-v1")"
    touch "${TEST_ROOT}/framework-ucsi-workaround-v1"

    # No DMI files present at all; if the marker guard works, the script
    # returns before ever reading them.
    run bash "${PATCHED_SCRIPT}"

    [ "$status" -eq 0 ]
    [ ! -f "${STUB_BIN}/rpm-ostree.log" ]
}
