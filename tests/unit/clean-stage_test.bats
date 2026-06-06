#!/usr/bin/env bats
# Unit tests for build_files/shared/clean-stage.sh.
# Run with: bats tests/unit/clean-stage_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
CLEAN_STAGE="${SCRIPT_DIR}/../../build_files/shared/clean-stage.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/clean-stage.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    DNF5_LOG="${TEST_ROOT}/dnf5.log"
    SYSTEMCTL_LOG="${TEST_ROOT}/systemctl.log"

    mkdir -p "${STUB_BIN}"

    # Minimal filesystem layout the script expects to find / clean up
    mkdir -p "${TEST_ROOT}/usr/lib/systemd/system"
    mkdir -p "${TEST_ROOT}/var/cache/libdnf5"
    mkdir -p "${TEST_ROOT}/var/cache/rpm-ostree"
    mkdir -p "${TEST_ROOT}/var/log"
    mkdir -p "${TEST_ROOT}/var/tmp"
    touch "${TEST_ROOT}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"
    touch "${TEST_ROOT}/.gitkeep"
    mkdir -p "${TEST_ROOT}/tmp/leftover"
    mkdir -p "${TEST_ROOT}/boot/efi"
    mkdir -p "${TEST_ROOT}/run/dbus"

    export PATH="${STUB_BIN}:${PATH}"
    export CLEAN_ROOT="${TEST_ROOT}"
    export DNF5_LOG
    export SYSTEMCTL_LOG
    unset DNF5_FAIL_MATCH DNF5_FAIL_CODE

    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${DNF5_LOG}"
if [[ -n "${DNF5_FAIL_MATCH:-}" && "$*" == *"${DNF5_FAIL_MATCH}"* ]]; then
    exit "${DNF5_FAIL_CODE:-1}"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/dnf5"

    cat > "${STUB_BIN}/systemctl" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG}"
exit 0
EOF
    chmod +x "${STUB_BIN}/systemctl"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ──────────────────────────────────────────────────────────────────────────────
# dnf5 calls
# ──────────────────────────────────────────────────────────────────────────────

@test "clean-stage: calls dnf5 config-manager setopt keepcache=0" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    grep -q "config-manager setopt keepcache=0" "${DNF5_LOG}"
}

@test "clean-stage: calls dnf5 versionlock clear" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    grep -q "versionlock clear" "${DNF5_LOG}"
}

# ──────────────────────────────────────────────────────────────────────────────
# systemctl calls
# ──────────────────────────────────────────────────────────────────────────────

@test "clean-stage: disables flatpak-add-fedora-repos.service" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    grep -q "disable flatpak-add-fedora-repos.service" "${SYSTEMCTL_LOG}"
}

@test "clean-stage: masks flatpak-add-fedora-repos.service" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    grep -q "mask flatpak-add-fedora-repos.service" "${SYSTEMCTL_LOG}"
}

# ──────────────────────────────────────────────────────────────────────────────
# File and directory removals
# ──────────────────────────────────────────────────────────────────────────────

@test "clean-stage: removes flatpak-add-fedora-repos.service unit file" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ ! -f "${TEST_ROOT}/usr/lib/systemd/system/flatpak-add-fedora-repos.service" ]
}

@test "clean-stage: removes .gitkeep" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ ! -e "${TEST_ROOT}/.gitkeep" ]
}

@test "clean-stage: removes /var subdirs except cache" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ ! -d "${TEST_ROOT}/var/log" ]
    [ ! -d "${TEST_ROOT}/var/tmp" ]
    [ -d "${TEST_ROOT}/var/cache" ]
}

@test "clean-stage: preserves /var/cache/libdnf5 and rpm-ostree" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/var/cache/libdnf5" ]
    [ -d "${TEST_ROOT}/var/cache/rpm-ostree" ]
}

@test "clean-stage: removes other /var/cache subdirs" {
    mkdir -p "${TEST_ROOT}/var/cache/some-tool"
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ ! -d "${TEST_ROOT}/var/cache/some-tool" ]
}

@test "clean-stage: clears /tmp contents but recreates the directory" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/tmp" ]
    [ ! -d "${TEST_ROOT}/tmp/leftover" ]
}

@test "clean-stage: clears /boot contents but recreates the directory" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/boot" ]
    [ ! -d "${TEST_ROOT}/boot/efi" ]
}

@test "clean-stage: clears /run contents but recreates the directory" {
    run bash "${CLEAN_STAGE}"
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/run" ]
    [ ! -d "${TEST_ROOT}/run/dbus" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Error propagation
# ──────────────────────────────────────────────────────────────────────────────

@test "clean-stage: fails when dnf5 versionlock clear fails" {
    export DNF5_FAIL_MATCH="versionlock clear"
    export DNF5_FAIL_CODE=1
    run bash "${CLEAN_STAGE}"
    [ "$status" -ne 0 ]
}
