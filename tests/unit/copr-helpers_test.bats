#!/usr/bin/env bats
# Unit tests for build_files/shared/copr-helpers.sh.
# Run with: bats tests/unit/copr-helpers_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
COPR_HELPERS_LIB="${SCRIPT_DIR}/../../build_files/shared/copr-helpers.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/copr-helpers.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/bin"
    DNF5_LOG="${TEST_ROOT}/dnf5.log"

    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"
    export COPR_HELPERS_LIB
    export DNF5_LOG
    unset DNF5_FAIL_MATCH
    unset DNF5_FAIL_CODE

    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${DNF5_LOG}"
if [[ -n "${DNF5_FAIL_MATCH:-}" && "$*" == *"${DNF5_FAIL_MATCH}"* ]]; then
    exit "${DNF5_FAIL_CODE:-1}"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/dnf5"

    # shellcheck source=../../build_files/shared/copr-helpers.sh
    source "${COPR_HELPERS_LIB}"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "copr_install_isolated: installs packages with isolated repo flow" {
    run copr_install_isolated atim/starship starship zsh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing starship zsh from COPR atim/starship (isolated)"* ]]
    [[ "$output" == *"Installed starship zsh from atim/starship"* ]]

    mapfile -t calls < "${DNF5_LOG}"
    [ "${#calls[@]}" -eq 3 ]
    [ "${calls[0]}" = "-y copr enable atim/starship" ]
    [ "${calls[1]}" = "-y copr disable atim/starship" ]
    [ "${calls[2]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:atim:starship starship zsh" ]
}

@test "copr_install_isolated: propagates dnf5 install failure" {
    export DNF5_FAIL_MATCH=" install "
    export DNF5_FAIL_CODE=23

    run bash -c 'source "$COPR_HELPERS_LIB"; copr_install_isolated atim/starship starship'

    [ "$status" -eq 23 ]
    [[ "$output" == *"Installing starship from COPR atim/starship (isolated)"* ]]
    [[ "$output" != *"Installed starship from atim/starship"* ]]

    mapfile -t calls < "${DNF5_LOG}"
    [ "${#calls[@]}" -eq 3 ]
}

@test "copr_install_isolated: empty package list returns error without calling dnf5" {
    run copr_install_isolated atim/starship

    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: No packages specified for copr_install_isolated"* ]]
    [ ! -f "${DNF5_LOG}" ]
}
