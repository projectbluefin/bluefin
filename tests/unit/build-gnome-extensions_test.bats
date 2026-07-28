#!/usr/bin/env bats
# Unit tests for build_files/shared/build-gnome-extensions.sh.
# Run with: bats tests/unit/build-gnome-extensions_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/../../build_files/shared/build-gnome-extensions.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/build-gnome-extensions.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    COMMAND_LOG="${TEST_ROOT}/commands.log"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"
    export COMMAND_LOG

    for command in glib-compile-schemas make unzip mv rm meson gradia-build; do
        cat > "${STUB_BIN}/${command}" <<'EOF'
#!/usr/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "${COMMAND_LOG}"
exit 0
EOF
        chmod +x "${STUB_BIN}/${command}"
    done

    PATCHED_SCRIPT="${TEST_ROOT}/build-gnome-extensions-patched.sh"
    sed "s|bash /usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/build.sh|gradia-build|" \
        "${SOURCE_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "build-gnome-extensions: compiles schemas and runs extension build tools" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q '^glib-compile-schemas ' "${COMMAND_LOG}"
    grep -q '^make ' "${COMMAND_LOG}"
    grep -q '^unzip ' "${COMMAND_LOG}"
    grep -q '^meson setup ' "${COMMAND_LOG}"
    grep -q '^meson install ' "${COMMAND_LOG}"
    grep -q '^gradia-build ' "${COMMAND_LOG}"
}

@test "build-gnome-extensions: removes the temporary extension tree" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q '^rm -rf /usr/share/gnome-shell/extensions/tmp$' "${COMMAND_LOG}"
}

@test "build-gnome-extensions: fails when a build command fails" {
    cat > "${STUB_BIN}/make" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
    chmod +x "${STUB_BIN}/make"

    run bash "${PATCHED_SCRIPT}"
    [ "$status" -ne 0 ]
}
