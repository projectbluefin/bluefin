#!/usr/bin/env bats
# Unit tests for build_files/base/20-tests.sh.
# Run with: bats tests/unit/20-tests_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/../../build_files/base/20-tests.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/20-tests.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/etc/containers" \
        "${TEST_ROOT}/usr/bin" \
        "${TEST_ROOT}/usr/share/ublue-os/just" \
        "${TEST_ROOT}/usr/share/ublue-os/homebrew" \
        "${TEST_ROOT}/usr/share/flatpak/preinstall.d" \
        "${TEST_ROOT}/usr/lib/systemd/system"

    touch "${TEST_ROOT}/etc/containers/signing-key.pub" \
        "${TEST_ROOT}/etc/containers/backup-key.pub" \
        "${TEST_ROOT}/usr/bin/ujust" \
        "${TEST_ROOT}/usr/share/ublue-os/homebrew/fonts.Brewfile" \
        "${TEST_ROOT}/usr/share/flatpak/preinstall.d/bazaar.preinstall"
    touch "${TEST_ROOT}/usr/share/ublue-os/just/00-entry.just" \
        "${TEST_ROOT}/usr/share/ublue-os/just/apps.just" \
        "${TEST_ROOT}/usr/share/ublue-os/just/default.just" \
        "${TEST_ROOT}/usr/share/ublue-os/just/system.just" \
        "${TEST_ROOT}/usr/share/ublue-os/just/update.just"
    cat > "${TEST_ROOT}/etc/containers/policy.json" <<'EOF'
{"transports":{"docker":{"ghcr.io/ublue-os":[{"keyPaths":["signing-key.pub","backup-key.pub"]}]}}}
EOF

    export TEST_ROOT STUB_BIN PATH="${STUB_BIN}:${PATH}"
    export IMAGE_NAME=bluefin

    cat > "${STUB_BIN}/jq" <<'EOF'
#!/usr/bin/bash
echo "${TEST_ROOT}/etc/containers/$([[ "$*" == *keyPaths[1]* ]] && echo backup-key.pub || echo signing-key.pub)"
EOF
    cat > "${STUB_BIN}/sha256sum" <<'EOF'
#!/usr/bin/bash
cat >/dev/null
exit 0
EOF
    cat > "${STUB_BIN}/stat" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == *"%{VENDOR}"* ]]; then
    echo "negativo17.org"
    exit 0
fi
# Treat all important and NVIDIA packages as installed; unwanted packages absent.
case "$*" in
    *fedora-flathub-remote*|*fedora-logos*|*fedora-third-party*|*gnome-software*|*podman-docker*) exit 1 ;;
esac
exit 0
EOF
    cat > "${STUB_BIN}/systemctl" <<'EOF'
#!/usr/bin/bash
echo enabled
EOF
    for command in jq sha256sum stat rpm systemctl; do
        chmod +x "${STUB_BIN}/${command}"
    done

    PATCHED_SCRIPT="${TEST_ROOT}/20-tests-patched.sh"
    sed \
        -e "s|/etc/containers|${TEST_ROOT}/etc/containers|g" \
        -e "s|/usr/|${TEST_ROOT}/usr/|g" \
        "${SOURCE_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "20-tests: passes when required image state is present" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
}

@test "20-tests: rejects an unwanted package" {
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == *"fedora-logos"* ]]; then
    exit 0
fi
if [[ "$*" == *"%{VENDOR}"* ]]; then
    echo "negativo17.org"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm"

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -ne 0 ]
}

@test "20-tests: checks NVIDIA packages for NVIDIA images" {
    export IMAGE_NAME=bluefin-nvidia
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == *"kmod-nvidia"* ]]; then
    exit 1
fi
if [[ "$*" == *"%{VENDOR}"* ]]; then
    echo "negativo17.org"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm"

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -ne 0 ]
}
