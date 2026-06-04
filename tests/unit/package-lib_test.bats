#!/usr/bin/env bats
# Unit tests for build_files/shared/package-lib.sh.
# Run with: bats tests/unit/package-lib_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
PACKAGE_LIB="${SCRIPT_DIR}/../../build_files/shared/package-lib.sh"

setup() {
    # Create a temp bin dir with stub commands so real dnf5/rpm are never called.
    STUB_BIN="$(mktemp -d)"
    export PATH="${STUB_BIN}:${PATH}"

    # Default stubs — can be overridden per test.
    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
echo "dnf5 $*"
exit 0
EOF
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
# Simulate "all packages installed" by default.
if [[ "$1" == "-q" ]]; then
    exit 0
elif [[ "$1" == "-qa" ]]; then
    # Return the packages listed after any flags
    shift
    while [[ "${1:-}" == --* ]]; do shift; done
    printf '%s\n' "$@"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/dnf5" "${STUB_BIN}/rpm"

    # Source the library under test.
    # shellcheck source=../../build_files/shared/package-lib.sh
    source "${PACKAGE_LIB}"
}

teardown() {
    rm -rf "${STUB_BIN}"
}

# ──────────────────────────────────────────────────────────────────────────────
# install_fedora_packages
# ──────────────────────────────────────────────────────────────────────────────

@test "install_fedora_packages: empty array prints message and returns 0" {
    declare -a pkgs=()
    run install_fedora_packages pkgs
    [ "$status" -eq 0 ]
    [[ "$output" == *"no packages to install"* ]]
}

@test "install_fedora_packages: single package calls dnf5 install" {
    declare -a pkgs=(vim)
    run install_fedora_packages pkgs
    [ "$status" -eq 0 ]
    [[ "$output" == *"dnf5"*"-y"*"install"*"vim"* ]]
}

@test "install_fedora_packages: multiple packages calls dnf5 install with all args" {
    declare -a pkgs=(vim git curl)
    run install_fedora_packages pkgs
    [ "$status" -eq 0 ]
    [[ "$output" == *"vim"* ]]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"curl"* ]]
}

@test "install_fedora_packages: propagates dnf5 failure" {
    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
    declare -a pkgs=(doesnotexist)
    run install_fedora_packages pkgs
    [ "$status" -ne 0 ]
}

# ──────────────────────────────────────────────────────────────────────────────
# remove_excluded_packages
# ──────────────────────────────────────────────────────────────────────────────

@test "remove_excluded_packages: empty array returns 0 without calling dnf5" {
    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
echo "dnf5 called unexpectedly"
exit 1
EOF
    declare -a pkgs=()
    run remove_excluded_packages pkgs
    [ "$status" -eq 0 ]
    [[ "$output" != *"dnf5 called unexpectedly"* ]]
}

@test "remove_excluded_packages: skips removal when no packages are installed" {
    # rpm -qa returns nothing → nothing to remove
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$1" == "-qa" ]]; then
    exit 0  # empty output
fi
exit 0
EOF
    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
echo "dnf5 remove called unexpectedly"
exit 1
EOF
    declare -a pkgs=(vim git)
    run remove_excluded_packages pkgs
    [ "$status" -eq 0 ]
    [[ "$output" == *"No excluded packages"* ]]
    [[ "$output" != *"dnf5 remove called unexpectedly"* ]]
}

@test "remove_excluded_packages: removes packages that are installed" {
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
if [[ "$1" == "-qa" ]]; then
    shift
    while [[ "${1:-}" == --* ]]; do shift; done
    printf '%s\n' "$@"
fi
exit 0
EOF
    declare -a pkgs=(vim git)
    run remove_excluded_packages pkgs
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removing"* ]]
    [[ "$output" == *"dnf5"*"-y"*"remove"* ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# assert_packages_present
# ──────────────────────────────────────────────────────────────────────────────

@test "assert_packages_present: succeeds when all packages are installed" {
    # Default rpm stub exits 0 for -q (package found)
    declare -a pkgs=(vim git curl)
    run assert_packages_present pkgs
    [ "$status" -eq 0 ]
    [[ "$output" == *"All 3 required packages are present"* ]]
}

@test "assert_packages_present: exits 1 and lists missing packages" {
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
# Simulate "vim" missing, everything else installed
if [[ "$1" == "-q" && "$2" == "vim" ]]; then
    exit 1
fi
exit 0
EOF
    declare -a pkgs=(vim git)
    run assert_packages_present pkgs
    [ "$status" -eq 1 ]
    [[ "$output" == *"vim"* ]]
    [[ "$output" == *"ERROR"* ]]
}

@test "assert_packages_present: exits 1 when multiple packages are missing" {
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
    declare -a pkgs=(vim git curl)
    run assert_packages_present pkgs
    [ "$status" -eq 1 ]
    [[ "$output" == *"vim"* ]]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"curl"* ]]
}

@test "assert_packages_present: empty array succeeds" {
    declare -a pkgs=()
    run assert_packages_present pkgs
    [ "$status" -eq 0 ]
    [[ "$output" == *"All 0 required packages are present"* ]]
}
