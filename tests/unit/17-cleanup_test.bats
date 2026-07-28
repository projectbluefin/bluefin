#!/usr/bin/env bats
# Unit tests for build_files/base/17-cleanup.sh.
# Run with: bats tests/unit/17-cleanup_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
CLEANUP_SCRIPT="${SCRIPT_DIR}/../../build_files/base/17-cleanup.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/17-cleanup.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"

    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/usr/share/applications"
    mkdir -p "${TEST_ROOT}/usr/lib/modules"

    export PATH="${STUB_BIN}:${PATH}"

    # Stub commands that require a real system environment
    for cmd in systemctl flatpak; do
        cat > "${STUB_BIN}/${cmd}" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
        chmod +x "${STUB_BIN}/${cmd}"
    done

    # Default rpm stub: no kernel installed (all module dirs are orphans)
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
    chmod +x "${STUB_BIN}/rpm"

    # Patch absolute paths to use TEST_ROOT, stub source of disable-repos.sh,
    # and use PATH-based rpm
    PATCHED_SCRIPT="${TEST_ROOT}/17-cleanup-patched.sh"
    sed \
        -e "s|/usr/share/applications/|${TEST_ROOT}/usr/share/applications/|g" \
        -e "s|/usr/lib/modules/|${TEST_ROOT}/usr/lib/modules/|g" \
        -e "s|/usr/bin/rpm|rpm|g" \
        -e "s|source /ctx/build_files/shared/disable-repos.sh|disable_third_party_repos() { :; }|g" \
        "${CLEANUP_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT TEST_ROOT STUB_BIN
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Desktop file hiding
# ──────────────────────────────────────────────────────────────────────────────

@test "17-cleanup: Hidden=true is appended after [Desktop Entry] in fish.desktop" {
    printf '[Desktop Entry]\nName=Fish\nExec=fish\n' \
        > "${TEST_ROOT}/usr/share/applications/fish.desktop"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "Hidden=true" "${TEST_ROOT}/usr/share/applications/fish.desktop"
}

@test "17-cleanup: Hidden=true is appended to htop.desktop when present" {
    printf '[Desktop Entry]\nName=Htop\n' \
        > "${TEST_ROOT}/usr/share/applications/htop.desktop"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "Hidden=true" "${TEST_ROOT}/usr/share/applications/htop.desktop"
}

@test "17-cleanup: nvtop.desktop without [Desktop Entry] is not modified" {
    printf 'Name=Nvtop\nExec=nvtop\n' \
        > "${TEST_ROOT}/usr/share/applications/nvtop.desktop"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # No [Desktop Entry] header means sed changes nothing
    ! grep -q "Hidden=true" "${TEST_ROOT}/usr/share/applications/nvtop.desktop"
}

@test "17-cleanup: desktop file hiding is skipped when file does not exist" {
    # fish.desktop absent — script must not error on missing file
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
}

@test "17-cleanup: all three known desktop files are hidden when present" {
    for name in fish htop nvtop; do
        printf '[Desktop Entry]\nName=%s\n' "${name}" \
            > "${TEST_ROOT}/usr/share/applications/${name}.desktop"
    done
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    for name in fish htop nvtop; do
        grep -q "Hidden=true" "${TEST_ROOT}/usr/share/applications/${name}.desktop"
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# systemctl / flatpak stubs (smoke test — confirms script reaches completion)
# ──────────────────────────────────────────────────────────────────────────────

@test "17-cleanup: script completes successfully with all stubs in place" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
}

@test "17-cleanup: systemctl is invoked for required services" {
    # Capture systemctl calls via a logging stub
    cat > "${STUB_BIN}/systemctl" <<'EOF'
#!/usr/bin/bash
echo "systemctl $*" >> "${STUB_BIN}/systemctl.log"
exit 0
EOF
    export STUB_BIN
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "enable podman-auto-update.timer" "${STUB_BIN}/systemctl.log"
    grep -q "enable ublue-system-setup.service" "${STUB_BIN}/systemctl.log"
    grep -q "disable rpm-ostreed-automatic.timer" "${STUB_BIN}/systemctl.log"
}

# ──────────────────────────────────────────────────────────────────────────────
# orphan kernel module cleanup
# ──────────────────────────────────────────────────────────────────────────────

@test "17-cleanup: orphan kernel module dir is removed when no RPM installed" {
    mkdir -p "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -d "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64" ]
    [[ "$output" == *"Removing orphan"* ]]
}

@test "17-cleanup: kernel module dir is preserved when RPM is installed" {
    mkdir -p "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64"
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64" ]
}

@test "17-cleanup: only orphan dirs are removed, installed kernel dirs preserved" {
    mkdir -p "${TEST_ROOT}/usr/lib/modules/6.12.0-orphan.fc42.x86_64"
    mkdir -p "${TEST_ROOT}/usr/lib/modules/6.12.0-installed.fc42.x86_64"

    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == *"installed"* ]]; then
    exit 0
fi
exit 1
EOF

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -d "${TEST_ROOT}/usr/lib/modules/6.12.0-orphan.fc42.x86_64" ]
    [ -d "${TEST_ROOT}/usr/lib/modules/6.12.0-installed.fc42.x86_64" ]
}
