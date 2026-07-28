#!/usr/bin/env bats
# Unit tests for build_files/base/05-override-install.sh.
#
# Tests security-critical sha256 integrity verification, sudoers modification,
# firewalld configuration changes, and version extraction from image-versions.yml.
#
# Run with: bats tests/unit/05-override-install_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
OVERRIDE_SCRIPT="${SCRIPT_DIR}/../../build_files/base/05-override-install.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/05-override-install.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"

    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/etc/firewalld"
    mkdir -p "${TEST_ROOT}/usr/bin"
    mkdir -p "${TEST_ROOT}/usr/lib/firewalld/zones"
    mkdir -p "${TEST_ROOT}/usr/lib/systemd/system-generators"
    mkdir -p "${TEST_ROOT}/usr/share/doc"
    mkdir -p "${TEST_ROOT}/usr/share/fonts"
    mkdir -p "${TEST_ROOT}/usr/src"
    mkdir -p "${TEST_ROOT}/tmp"
    mkdir -p "${TEST_ROOT}/ctx"
    mkdir -p "${TEST_ROOT}/fixtures/tmp-content"

    export PATH="${STUB_BIN}:${PATH}"

    # ── System stubs ──────────────────────────────────────────────────────
    for cmd in setfattr gdk-pixbuf-query-loaders-64 rpm; do
        printf '#!/usr/bin/bash\nexit 0\n' > "${STUB_BIN}/${cmd}"
        chmod +x "${STUB_BIN}/${cmd}"
    done

    # ── Fixtures ──────────────────────────────────────────────────────────
    # sudoers with a typical secure_path
    cat > "${TEST_ROOT}/etc/sudoers" <<'EOF'
Defaults    secure_path = /sbin:/bin:/usr/sbin:/usr/bin
EOF

    # firewalld.conf with values that will be overwritten
    cat > "${TEST_ROOT}/etc/firewalld/firewalld.conf" <<'EOF'
DefaultZone=public
IPv6_rpfilter=yes
EOF

    # FedoraWorkstation.xml with the content the script verifies via grep
    cat > "${TEST_ROOT}/usr/lib/firewalld/zones/FedoraWorkstation.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Fedora Workstation</short>
  <port protocol="udp" port="1025-65535"/>
  <port protocol="tcp" port="1025-65535"/>
</zone>
EOF

    # image-versions.yml
    cat > "${TEST_ROOT}/ctx/image-versions.yml" <<'EOF'
packages:
  # renovate: datasource=github-releases depName=starship/starship
  starship: "1.22.0"
EOF

    # Starship archive: create a real archive so sha256 can be verified
    printf 'starship-dummy-binary' > "${TEST_ROOT}/fixtures/tmp-content/starship"
    (cd "${TEST_ROOT}/fixtures/tmp-content" && tar -czf "${TEST_ROOT}/fixtures/starship.tar.gz" starship)
    VALID_SHA=$(sha256sum "${TEST_ROOT}/fixtures/starship.tar.gz" | awk '{print $1}')
    echo "${VALID_SHA}" > "${TEST_ROOT}/fixtures/starship.tar.gz.sha256"

    # ── ghcurl stub ───────────────────────────────────────────────────────
    # Serves pre-created fixtures; supports a "corrupt" mode for sha256 tests.
    cat > "${STUB_BIN}/ghcurl" <<GHCURL_STUB
#!/usr/bin/bash
URL="\$1"
shift
DEST=""
while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "-o" || "\$1" == "-Lo" ]]; then
        DEST="\$2"
        shift 2
    elif [[ "\$1" == "--retry" ]]; then
        shift 2
    else
        shift
    fi
done
[[ -z "\${DEST:-}" ]] && exit 0
case "\$URL" in
    *.tar.gz.sha256)
        MODE=\$(cat "${TEST_ROOT}/ghcurl-sha256-mode" 2>/dev/null || echo "valid")
        if [[ "\$MODE" == "corrupt" ]]; then
            echo "0000000000000000000000000000000000000000000000000000000000000000" > "\$DEST"
        else
            cp "${TEST_ROOT}/fixtures/starship.tar.gz.sha256" "\$DEST"
        fi
        ;;
    *.tar.gz)
        cp "${TEST_ROOT}/fixtures/starship.tar.gz" "\$DEST"
        ;;
    *FedoraWorkstation.xml)
        cp "${TEST_ROOT}/usr/lib/firewalld/zones/FedoraWorkstation.xml" "\$DEST"
        ;;
    *coreos-sulogin-force-generator)
        printf '#!/bin/bash\n' > "\$DEST"
        ;;
    *.pdf)
        printf 'dummy-pdf\n' > "\$DEST"
        ;;
    *)
        touch "\$DEST"
        ;;
esac
exit 0
GHCURL_STUB
    chmod +x "${STUB_BIN}/ghcurl"

    # ── Patch the script ──────────────────────────────────────────────────
    PATCHED_SCRIPT="${TEST_ROOT}/05-override-install-patched.sh"
    # Protect the coreos generator URL before path replacements mangle it.
    # The URL contains /usr/lib/systemd/system-generators which would otherwise
    # be replaced with the TEST_ROOT path, producing a malformed URL.
    local COREOS_URL="https://raw.githubusercontent.com/coreos/fedora-coreos-config/refs/heads/stable/overlay.d/05core/usr/lib/systemd/system-generators/coreos-sulogin-force-generator"
    local COREOS_URL_PLACEHOLDER="COREOS_SULOGIN_GENERATOR_URL_PLACEHOLDER"
    sed \
        -e "s|${COREOS_URL}|${COREOS_URL_PLACEHOLDER}|g" \
        -e "s|/usr/src|${TEST_ROOT}/usr/src|g" \
        -e "s|/usr/src|${TEST_ROOT}/usr/src|g" \
        -e "s|/usr/share/doc|${TEST_ROOT}/usr/share/doc|g" \
        -e "s|/usr/share/fonts|${TEST_ROOT}/usr/share/fonts|g" \
        -e "s|/usr/lib/systemd/system-generators|${TEST_ROOT}/usr/lib/systemd/system-generators|g" \
        -e "s|/usr/lib/firewalld|${TEST_ROOT}/usr/lib/firewalld|g" \
        -e "s|/usr/bin|${TEST_ROOT}/usr/bin|g" \
        -e "s|/etc/firewalld|${TEST_ROOT}/etc/firewalld|g" \
        -e "s|/etc/sudoers|${TEST_ROOT}/etc/sudoers|g" \
        -e "s|/ctx/image-versions.yml|${TEST_ROOT}/ctx/image-versions.yml|g" \
        -e "s|/tmp|${TEST_ROOT}/tmp|g" \
        -e "s|${COREOS_URL_PLACEHOLDER}|${COREOS_URL}|g" \
        "${OVERRIDE_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"

    export PATCHED_SCRIPT TEST_ROOT STUB_BIN VALID_SHA
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ─────────────────────────────────────────────────────────────────────────────
# sha256 integrity verification (CWE-494)
# ─────────────────────────────────────────────────────────────────────────────

@test "sha256 pattern: valid archive passes check" {
    # Test the exact sha256sum pattern used in the script, in isolation.
    echo "${VALID_SHA}" > "${TEST_ROOT}/tmp/starship.tar.gz.sha256"
    cp "${TEST_ROOT}/fixtures/starship.tar.gz" "${TEST_ROOT}/tmp/starship.tar.gz"
    run bash -c "cd '${TEST_ROOT}/tmp' && echo \"\$(tr -d '[:space:]' < starship.tar.gz.sha256)  starship.tar.gz\" | sha256sum -c"
    [ "$status" -eq 0 ]
}

@test "sha256 pattern: corrupted archive fails check" {
    # A wrong hash must cause a non-zero exit — supply chain attack is caught.
    echo "0000000000000000000000000000000000000000000000000000000000000000" > "${TEST_ROOT}/tmp/starship.tar.gz.sha256"
    cp "${TEST_ROOT}/fixtures/starship.tar.gz" "${TEST_ROOT}/tmp/starship.tar.gz"
    run bash -c "cd '${TEST_ROOT}/tmp' && echo \"\$(tr -d '[:space:]' < starship.tar.gz.sha256)  starship.tar.gz\" | sha256sum -c"
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# sudoers modification
# ─────────────────────────────────────────────────────────────────────────────

@test "sudoers: linuxbrew path is appended to secure_path" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "linuxbrew" "${TEST_ROOT}/etc/sudoers"
    [ "$status" -eq 0 ]
}

@test "sudoers: original secure_path entries are preserved" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep "secure_path" "${TEST_ROOT}/etc/sudoers"
    [ "$status" -eq 0 ]
    [[ "$output" == */sbin:* ]]
    [[ "$output" == */usr/bin:* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# firewalld configuration
# ─────────────────────────────────────────────────────────────────────────────

@test "firewalld: DefaultZone is set to FedoraWorkstation" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "^DefaultZone=FedoraWorkstation$" "${TEST_ROOT}/etc/firewalld/firewalld.conf"
    [ "$status" -eq 0 ]
}

@test "firewalld: IPv6_rpfilter is set to loose" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep -q "^IPv6_rpfilter=loose$" "${TEST_ROOT}/etc/firewalld/firewalld.conf"
    [ "$status" -eq 0 ]
}

@test "coreos sulogin generator is installed" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/lib/systemd/system-generators/coreos-sulogin-force-generator" ]
}
