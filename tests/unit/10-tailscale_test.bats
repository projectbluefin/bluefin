#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/10-tailscale.sh
# Run with: bats tests/unit/10-tailscale_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../../system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/10-tailscale.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/10-tailscale.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"

    # Stub tailscale — log its arguments
    cat > "${STUB_BIN}/tailscale" <<EOF
#!/usr/bin/bash
echo "tailscale \$*" >> "${STUB_BIN}/tailscale.log"
exit 0
EOF
    chmod +x "${STUB_BIN}/tailscale"

    # Stub getent — verify uid arg matches, return fixed passwd entry
    cat > "${STUB_BIN}/getent" <<'EOF'
#!/usr/bin/bash
[[ "$2" == "1000" ]] || exit 1
echo "testuser:x:1000:1000::/home/testuser:/bin/bash"
EOF
    chmod +x "${STUB_BIN}/getent"

    # Patch: replace source of libsetup.sh with a no-op version-script stub
    PATCHED_SCRIPT="${TEST_ROOT}/10-tailscale-patched.sh"
    sed \
        -e "s|source /usr/lib/ublue/setup-services/libsetup.sh|version-script() { return 0; }|g" \
        "${HOOK_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT TEST_ROOT STUB_BIN
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "10-tailscale: tailscale set --operator called with username for PKEXEC_UID" {
    export PKEXEC_UID=1000
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q -- "--operator=testuser" "${STUB_BIN}/tailscale.log"
}
