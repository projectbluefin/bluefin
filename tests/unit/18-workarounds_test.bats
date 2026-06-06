#!/usr/bin/env bats
# Unit tests for build_files/base/18-workarounds.sh.
# Run with: bats tests/unit/18-workarounds_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
WORKAROUNDS_SCRIPT="${SCRIPT_DIR}/../../build_files/base/18-workarounds.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/18-workarounds.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"

    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/usr/share/ublue-os/bling"
    mkdir -p "${TEST_ROOT}/usr/share/ublue-os/bluefin-cli"
    mkdir -p "${TEST_ROOT}/usr/share/doc/just"
    mkdir -p "${TEST_ROOT}/usr/lib/modules"

    export PATH="${STUB_BIN}:${PATH}"

    # Default rpm stub: no kernel installed (all module dirs are orphans)
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
exit 1
EOF
    chmod +x "${STUB_BIN}/rpm"

    # Patch absolute paths to use TEST_ROOT, and use PATH-based rpm
    PATCHED_SCRIPT="${TEST_ROOT}/18-workarounds-patched.sh"
    sed \
        -e "s|/usr/share/ublue-os/|${TEST_ROOT}/usr/share/ublue-os/|g" \
        -e "s|/usr/share/doc/just/|${TEST_ROOT}/usr/share/doc/just/|g" \
        -e "s|/usr/lib/modules/|${TEST_ROOT}/usr/lib/modules/|g" \
        -e "s|/usr/bin/rpm|rpm|g" \
        "${WORKAROUNDS_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"
    export PATCHED_SCRIPT TEST_ROOT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ──────────────────────────────────────────────────────────────────────────────
# bling copy
# ──────────────────────────────────────────────────────────────────────────────

@test "18-workarounds: bling.sh is copied to bluefin-cli" {
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.sh"
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.fish"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/share/ublue-os/bluefin-cli/bling.sh" ]
    [ -f "${TEST_ROOT}/usr/share/ublue-os/bluefin-cli/bling.fish" ]
}

@test "18-workarounds: bluefin-cli directory is created if absent" {
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.sh"
    rmdir "${TEST_ROOT}/usr/share/ublue-os/bluefin-cli"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/usr/share/ublue-os/bluefin-cli" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# just README removal
# ──────────────────────────────────────────────────────────────────────────────

@test "18-workarounds: locale README files (README.*.md) are removed from just docs" {
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.sh"
    touch "${TEST_ROOT}/usr/share/doc/just/README.md"
    touch "${TEST_ROOT}/usr/share/doc/just/README.es.md"
    touch "${TEST_ROOT}/usr/share/doc/just/README.zh.md"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # README.*.md only matches locale variants (README.es.md, README.zh.md), not README.md
    [ ! -f "${TEST_ROOT}/usr/share/doc/just/README.es.md" ]
    [ ! -f "${TEST_ROOT}/usr/share/doc/just/README.zh.md" ]
    # Plain README.md does not match README.*.md glob and must be preserved
    [ -f "${TEST_ROOT}/usr/share/doc/just/README.md" ]
}

@test "18-workarounds: non-README files in just docs are preserved" {
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.sh"
    touch "${TEST_ROOT}/usr/share/doc/just/README.md"
    touch "${TEST_ROOT}/usr/share/doc/just/CHANGELOG"
    touch "${TEST_ROOT}/usr/share/doc/just/LICENSE"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/share/doc/just/CHANGELOG" ]
    [ -f "${TEST_ROOT}/usr/share/doc/just/LICENSE" ]
}

# ──────────────────────────────────────────────────────────────────────────────
# orphan kernel module cleanup
# ──────────────────────────────────────────────────────────────────────────────

@test "18-workarounds: orphan kernel module dir is removed when no RPM installed" {
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.sh"
    mkdir -p "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -d "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64" ]
    [[ "$output" == *"Removing orphan"* ]]
}

@test "18-workarounds: kernel module dir is preserved when RPM is installed" {
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.sh"
    mkdir -p "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64"
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -d "${TEST_ROOT}/usr/lib/modules/6.12.0-200.fc42.x86_64" ]
}

@test "18-workarounds: only orphan dirs are removed, installed kernel dirs preserved" {
    touch "${TEST_ROOT}/usr/share/ublue-os/bling/bling.sh"
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
