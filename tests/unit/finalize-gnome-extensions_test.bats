#!/usr/bin/env bats
# Unit tests for build_files/shared/finalize-gnome-extensions.sh.
# Run with: bats tests/unit/finalize-gnome-extensions_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/../../build_files/shared/finalize-gnome-extensions.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/finalize-gnome-extensions.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    COMMAND_LOG="${TEST_ROOT}/commands.log"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"
    export COMMAND_LOG

    for command in rm glib-compile-schemas setfattr; do
        cat > "${STUB_BIN}/${command}" <<'EOF'
#!/usr/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "${COMMAND_LOG}"
exit 0
EOF
        chmod +x "${STUB_BIN}/${command}"
    done

    PATCHED_SCRIPT="${TEST_ROOT}/finalize-gnome-extensions-patched.sh"
    sed \
        -e "s|/usr/share/glib-2.0/schemas|${TEST_ROOT}/usr/share/glib-2.0/schemas|g" \
        -e "s|/usr/share/gnome-shell/extensions|${TEST_ROOT}/usr/share/gnome-shell/extensions|g" \
        "${SOURCE_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "finalize-gnome-extensions: recompiles shared schemas" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "^rm -f ${TEST_ROOT}/usr/share/glib-2.0/schemas/gschemas.compiled$" "${COMMAND_LOG}"
    grep -q "^glib-compile-schemas ${TEST_ROOT}/usr/share/glib-2.0/schemas$" "${COMMAND_LOG}"
}

@test "finalize-gnome-extensions: assigns the rechunker component" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q "^setfattr -n user.component -v gnome-extensions ${TEST_ROOT}/usr/share/gnome-shell/extensions/$" "${COMMAND_LOG}"
}

@test "finalize-gnome-extensions: fails when schema compilation fails" {
    cat > "${STUB_BIN}/glib-compile-schemas" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
    chmod +x "${STUB_BIN}/glib-compile-schemas"

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -ne 0 ]
}
