#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh
# Run with: bats tests/unit/99-flatpaks_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../../system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/99-flatpaks.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"
    export PREF_DIR="${TEST_ROOT}/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/defaults/pref"

    # Stub arch — return x86_64
    cat > "${STUB_BIN}/arch" <<'EOF'
#!/usr/bin/bash
echo "x86_64"
EOF
    chmod +x "${STUB_BIN}/arch"

    # Pre-populate firefox-config source with a dummy config file
    mkdir -p "${TEST_ROOT}/usr/share/ublue-os/firefox-config"
    echo "// bluefin pref" > "${TEST_ROOT}/usr/share/ublue-os/firefox-config/bluefin.js"

    # Patch: stub libsetup.sh, redirect flatpak extension path,
    # redirect firefox-config source, and use PATH-based cp
    PATCHED_SCRIPT="${TEST_ROOT}/99-flatpaks-patched.sh"
    sed \
        -e "s|source /usr/lib/ublue/setup-services/libsetup.sh|version-script() { return 0; }|g" \
        -e "s|/var/lib/flatpak/extension|${TEST_ROOT}/var/lib/flatpak/extension|g" \
        -e "s|/usr/share/ublue-os/firefox-config|${TEST_ROOT}/usr/share/ublue-os/firefox-config|g" \
        -e "s|/usr/bin/cp|cp|g" \
        "${HOOK_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT TEST_ROOT STUB_BIN PREF_DIR
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "99-flatpaks: firefox config file copied to extension path on x86_64" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${PREF_DIR}/bluefin.js" ]
}

# ponytail: documents known regression — glob is quoted in hook so bluefin*.js are never removed
@test "99-flatpaks: stale bluefin*.js files are NOT removed (quoted-glob bug)" {
    mkdir -p "${PREF_DIR}"
    echo "// stale" > "${PREF_DIR}/bluefin-stale.js"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # Bug: rm uses quoted glob, old file survives — test documents known regression
    [ -f "${PREF_DIR}/bluefin-stale.js" ]
}
