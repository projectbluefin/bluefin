#!/usr/bin/env bats
# Unit tests for build_files/base/03-packages.sh.
#
# Tests Fedora-version-specific package conditionals, COPR install calls,
# and excluded-package removal logic.
#
# Run with: bats tests/unit/03-packages_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
PACKAGES_SCRIPT="${SCRIPT_DIR}/../../build_files/base/03-packages.sh"
COPR_HELPERS="${SCRIPT_DIR}/../../build_files/shared/copr-helpers.sh"
PACKAGE_LIB="${SCRIPT_DIR}/../../build_files/shared/package-lib.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/03-packages.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    DNF5_LOG="${TEST_ROOT}/dnf5.log"

    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/usr/share/vulkan/icd.d"

    export PATH="${STUB_BIN}:${PATH}"
    export DNF5_LOG
    export FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"

    # ── dnf5 stub: log every invocation ──────────────────────────────────
    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
echo "dnf5 $*" >> "${DNF5_LOG}"
# Simulate: dnf5 repolist prints nothing (triggers fedora-multimedia add path)
if [[ "$1" == "repolist" ]]; then
    exit 0
fi
# Simulate: rpm -qa for remove_excluded_packages (nothing installed)
exit 0
EOF
    chmod +x "${STUB_BIN}/dnf5"

    # ── rpm stub: returns fedora version and handles -qa ─────────────────
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$1" == "-E" && "$2" == "%fedora" ]]; then
    echo "${FEDORA_MAJOR_VERSION}"
fi
# rpm -qa: return empty (no packages installed from EXCLUDED list)
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm"

    # ── Patch the script ──────────────────────────────────────────────────
    PATCHED_SCRIPT="${TEST_ROOT}/03-packages-patched.sh"
    sed \
        -e "s|source /ctx/build_files/shared/copr-helpers.sh|source ${COPR_HELPERS}|g" \
        -e "s|source /ctx/build_files/shared/package-lib.sh|source ${PACKAGE_LIB}|g" \
        -e "s|/usr/share/vulkan|${TEST_ROOT}/usr/share/vulkan|g" \
        "${PACKAGES_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"

    export PATCHED_SCRIPT TEST_ROOT STUB_BIN DNF5_LOG
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Fedora-version-specific package additions
# ─────────────────────────────────────────────────────────────────────────────

@test "f42: evolution-ews-core is included in package install" {
    export FEDORA_MAJOR_VERSION=42
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "evolution-ews-core" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

@test "f42: uld is included in package install" {
    export FEDORA_MAJOR_VERSION=42
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "uld" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

@test "f43: evolution-ews-core is included in package install" {
    export FEDORA_MAJOR_VERSION=43
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "evolution-ews-core" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

@test "f43: gnupg2-scdaemon is included in package install" {
    export FEDORA_MAJOR_VERSION=43
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "gnupg2-scdaemon" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

@test "f44: gnupg2-scdaemon is included in package install" {
    export FEDORA_MAJOR_VERSION=44
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "gnupg2-scdaemon" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

@test "f43: uld is NOT included (f42-only package)" {
    export FEDORA_MAJOR_VERSION=43
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # uld is an f42-only package; it must not appear for f43
    run grep -q "^dnf5.*install.* uld " "${DNF5_LOG}"
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Fedora 42 OpenCL swap (only on f42)
# ─────────────────────────────────────────────────────────────────────────────

@test "f42: OpenCL-ICD-Loader swap is invoked" {
    export FEDORA_MAJOR_VERSION=42
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "OpenCL-ICD-Loader" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

@test "f43: OpenCL-ICD-Loader swap is NOT invoked" {
    export FEDORA_MAJOR_VERSION=43
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "OpenCL-ICD-Loader" "${DNF5_LOG}"
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# COPR install is invoked for ublue-os/packages
# ─────────────────────────────────────────────────────────────────────────────

@test "copr_install_isolated is called for ublue-os/packages" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # copr_install_isolated calls dnf5 copr enable + dnf5 install
    run grep -q "ublue-os/packages" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Base packages: spot-check a few that must always be installed
# ─────────────────────────────────────────────────────────────────────────────

@test "distrobox is in the package install list" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "distrobox" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}

@test "tailscale is in the package install list" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "tailscale" "${DNF5_LOG}"
    [ "$status" -eq 0 ]
}
