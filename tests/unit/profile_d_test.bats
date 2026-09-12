#!/usr/bin/env bats
# Unit tests for system_files/shared/etc/profile.d/ scripts:
#   - 90-bluefin-starship.sh
#   - 91-bluefin-aliases.sh
# Run with: bats tests/unit/profile_d_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STARSHIP_SCRIPT="${REPO_ROOT}/system_files/shared/etc/profile.d/90-bluefin-starship.sh"
ALIASES_SCRIPT="${REPO_ROOT}/system_files/shared/etc/profile.d/91-bluefin-aliases.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/profile_d.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/bin"
    mkdir -p "${STUB_BIN}"
    ORIG_PATH="${PATH}"
    export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
    export PATH="${ORIG_PATH}"
    rm -rf "${TEST_ROOT}"
}

# ──────────────────────────────────────────────────────────────────────────────
# 90-bluefin-starship.sh tests
# ──────────────────────────────────────────────────────────────────────────────

@test "90-bluefin-starship: no-op when starship is absent from PATH and brew" {
    run bash -c "source '${STARSHIP_SCRIPT}'; echo 'SOURCE_EXIT_OK'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SOURCE_EXIT_OK" ]]
}

@test "90-bluefin-starship: initializes starship when starship is on PATH in bash" {
    cat > "${STUB_BIN}/starship" << 'EOF'
#!/usr/bin/bash
if [ "$1" = "init" ] && [ "$2" = "bash" ]; then
    echo "export STARSHIP_INIT_CALLED=1"
fi
EOF
    chmod +x "${STUB_BIN}/starship"

    run bash -c "source '${STARSHIP_SCRIPT}'; echo "VAL=\$STARSHIP_INIT_CALLED""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "VAL=1" ]]
}

@test "90-bluefin-starship: initializes starship from linuxbrew when not on PATH" {
    BREW_BIN="${TEST_ROOT}/var/home/linuxbrew/.linuxbrew/bin"
    mkdir -p "${BREW_BIN}"
    cat > "${BREW_BIN}/starship" << 'EOF'
#!/usr/bin/bash
if [ "$1" = "init" ] && [ "$2" = "bash" ]; then
    echo "export STARSHIP_BREW_INIT_CALLED=1"
fi
EOF
    chmod +x "${BREW_BIN}/starship"

    PATCHED_STARSHIP="${TEST_ROOT}/90-bluefin-starship.sh"
    sed "s|/var/home/linuxbrew/.linuxbrew/bin/starship|${BREW_BIN}/starship|g"         "${STARSHIP_SCRIPT}" > "${PATCHED_STARSHIP}"

    run bash -c "source '${PATCHED_STARSHIP}'; echo "VAL=\$STARSHIP_BREW_INIT_CALLED""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "VAL=1" ]]
}

@test "90-bluefin-starship: does not call starship init if shell is not bash" {
    cat > "${STUB_BIN}/starship" << 'EOF'
#!/usr/bin/bash
echo "export STARSHIP_INIT_CALLED=1"
EOF
    chmod +x "${STUB_BIN}/starship"

    PATCHED_STARSHIP="${TEST_ROOT}/90-bluefin-starship-nonbash.sh"
    sed 's/"bash"/"zsh"/g' "${STARSHIP_SCRIPT}" > "${PATCHED_STARSHIP}"

    run bash -c "source '${PATCHED_STARSHIP}'; echo "VAL=\${STARSHIP_INIT_CALLED:-0}""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "VAL=0" ]]
}

@test "90-bluefin-starship: unsets _starship_bin after sourcing" {
    cat > "${STUB_BIN}/starship" << 'EOF'
#!/usr/bin/bash
echo ""
EOF
    chmod +x "${STUB_BIN}/starship"

    run bash -c "source '${STARSHIP_SCRIPT}'; echo "BIN=\${_starship_bin:-UNSET}""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "BIN=UNSET" ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# 91-bluefin-aliases.sh tests
# ──────────────────────────────────────────────────────────────────────────────

@test "91-bluefin-aliases: rl alias is set when ramalama exists" {
    cat > "${STUB_BIN}/ramalama" << 'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/ramalama"

    run bash -c "shopt -s expand_aliases; source '${ALIASES_SCRIPT}'; alias rl"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias rl='ramalama'" ]]
}

@test "91-bluefin-aliases: rl alias is not set when ramalama is absent" {
    run bash -c "shopt -s expand_aliases; source '${ALIASES_SCRIPT}'; alias rl 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" ]]
}
