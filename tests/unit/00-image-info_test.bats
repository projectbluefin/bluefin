#!/usr/bin/env bats
# Unit tests for build_files/base/00-image-info.sh.
# Run with: bats tests/unit/00-image-info_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
IMAGE_INFO_SCRIPT="${SCRIPT_DIR}/../../build_files/base/00-image-info.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/00-image-info.${BATS_TEST_NUMBER:-0}.$$"

    mkdir -p "${TEST_ROOT}/usr/share/ublue-os"
    mkdir -p "${TEST_ROOT}/usr/lib"
    mkdir -p "${TEST_ROOT}/usr/sbin"
    mkdir -p "${TEST_ROOT}/usr/share/glib-2.0/schemas"

    # Stub os-release with typical Fedora fields
    cat > "${TEST_ROOT}/usr/lib/os-release" <<'EOF'
NAME="Fedora Linux"
VERSION="42 (Workstation Edition)"
ID=fedora
VERSION_ID=42
VERSION_CODENAME=""
PLATFORM_ID="platform:f42"
PRETTY_NAME="Fedora Linux 42 (Workstation Edition)"
ANSI_COLOR="0;38;2;60;110;180"
LOGO=fedora-logo-icon
CPE_NAME="cpe:/o:fedoraproject:fedora:42"
DEFAULT_HOSTNAME="fedora"
HOME_URL="https://fedoraproject.org/"
DOCUMENTATION_URL="https://docs.fedoraproject.org/en-US/fedora/f42/system-administrators-guide/"
SUPPORT_URL="https://ask.fedoraproject.org/"
BUG_REPORT_URL="https://bugzilla.redhat.com/"
REDHAT_BUGZILLA_PRODUCT="Fedora"
REDHAT_BUGZILLA_PRODUCT_VERSION=42
REDHAT_SUPPORT_PRODUCT="Fedora"
REDHAT_SUPPORT_PRODUCT_VERSION=42
SUPPORT_END=2025-05-13
VARIANT_ID=workstation
EFIDIR="fedora"
OSTREE_VERSION='42.20260101'
EOF

    # Stub grub2 script (only needs to exist for sed -i)
    echo 'EFIDIR="fedora"' > "${TEST_ROOT}/usr/sbin/grub2-switch-to-blscfg"

    # Stub gschema override for nvidia tests
    printf 'experimental-features=[]\n' \
        > "${TEST_ROOT}/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override"

    # Minimal required env vars
    export IMAGE_NAME="bluefin"
    export IMAGE_VENDOR="projectbluefin"
    export UBLUE_IMAGE_TAG="testing"
    export BASE_IMAGE_NAME="base-main"
    export FEDORA_MAJOR_VERSION="42"
    export VERSION="42.20260101"
    unset SHA_HEAD_SHORT

    # Patch all absolute paths to use TEST_ROOT
    PATCHED_SCRIPT="${TEST_ROOT}/00-image-info-patched.sh"
    sed \
        -e "s|/usr/share/ublue-os/image-info.json|${TEST_ROOT}/usr/share/ublue-os/image-info.json|g" \
        -e "s|/usr/lib/os-release|${TEST_ROOT}/usr/lib/os-release|g" \
        -e "s|/usr/sbin/grub2-switch-to-blscfg|${TEST_ROOT}/usr/sbin/grub2-switch-to-blscfg|g" \
        -e "s|/usr/share/ublue-os/fastfetch-user-count|${TEST_ROOT}/usr/share/ublue-os/fastfetch-user-count|g" \
        -e "s|/usr/share/ublue-os/bazaar-install-count|${TEST_ROOT}/usr/share/ublue-os/bazaar-install-count|g" \
        -e "s|/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override|${TEST_ROOT}/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override|g" \
        "${IMAGE_INFO_SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"

    export PATCHED_SCRIPT TEST_ROOT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ─────────────────────────────────────────────────────────────────────────────
# image-info.json — written correctly
# ─────────────────────────────────────────────────────────────────────────────

@test "image-info.json is created" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/share/ublue-os/image-info.json" ]
}

@test "image-info.json is valid JSON" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run python3 -c "import json,sys; json.load(open('${TEST_ROOT}/usr/share/ublue-os/image-info.json'))"
    [ "$status" -eq 0 ]
}

@test "image-info.json contains correct image-name" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run python3 -c "
import json, sys
d = json.load(open('${TEST_ROOT}/usr/share/ublue-os/image-info.json'))
sys.exit(0 if d['image-name'] == 'bluefin' else 1)
"
    [ "$status" -eq 0 ]
}

@test "image-info.json contains correct image-vendor" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run python3 -c "
import json, sys
d = json.load(open('${TEST_ROOT}/usr/share/ublue-os/image-info.json'))
sys.exit(0 if d['image-vendor'] == 'projectbluefin' else 1)
"
    [ "$status" -eq 0 ]
}

@test "image-info.json contains correct image-tag" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run python3 -c "
import json, sys
d = json.load(open('${TEST_ROOT}/usr/share/ublue-os/image-info.json'))
sys.exit(0 if d['image-tag'] == 'testing' else 1)
"
    [ "$status" -eq 0 ]
}

@test "image-info.json contains correct fedora-version" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run python3 -c "
import json, sys
d = json.load(open('${TEST_ROOT}/usr/share/ublue-os/image-info.json'))
sys.exit(0 if d['fedora-version'] == '42' else 1)
"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# image_flavor detection
# ─────────────────────────────────────────────────────────────────────────────

@test "image_flavor is 'main' for non-nvidia image" {
    export IMAGE_NAME="bluefin"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run python3 -c "
import json, sys
d = json.load(open('${TEST_ROOT}/usr/share/ublue-os/image-info.json'))
sys.exit(0 if d['image-flavor'] == 'main' else 1)
"
    [ "$status" -eq 0 ]
}

@test "image_flavor is 'nvidia' when IMAGE_NAME contains nvidia" {
    export IMAGE_NAME="bluefin-nvidia"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run python3 -c "
import json, sys
d = json.load(open('${TEST_ROOT}/usr/share/ublue-os/image-info.json'))
sys.exit(0 if d['image-flavor'] == 'nvidia' else 1)
"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# os-release mutations
# ─────────────────────────────────────────────────────────────────────────────

@test "IMAGE_ID is appended to os-release" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep 'IMAGE_ID=' "${TEST_ROOT}/usr/lib/os-release"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"bluefin"'* ]]
}

@test "IMAGE_VERSION is appended to os-release" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep 'IMAGE_VERSION=' "${TEST_ROOT}/usr/lib/os-release"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"42.20260101"'* ]]
}

@test "VERSION defaults to 00.00000000 when unset" {
    unset VERSION
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep 'IMAGE_VERSION=' "${TEST_ROOT}/usr/lib/os-release"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"00.00000000"'* ]]
}

@test "VARIANT_ID is rewritten to IMAGE_NAME in os-release" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep 'VARIANT_ID=' "${TEST_ROOT}/usr/lib/os-release"
    [ "$status" -eq 0 ]
    [[ "$output" == *'bluefin'* ]]
}

@test "Redhat bugzilla lines are removed from os-release" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    run grep 'REDHAT_BUGZILLA_PRODUCT' "${TEST_ROOT}/usr/lib/os-release"
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Placeholder files
# ─────────────────────────────────────────────────────────────────────────────

@test "fastfetch-user-count placeholder is written" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/share/ublue-os/fastfetch-user-count" ]
}

@test "bazaar-install-count placeholder is written" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/share/ublue-os/bazaar-install-count" ]
}
