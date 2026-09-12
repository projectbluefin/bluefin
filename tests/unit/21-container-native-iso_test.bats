#!/usr/bin/env bats
# Unit tests for build_files/base/21-container-native-iso.sh.
# Run with: bats tests/unit/21-container-native-iso_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
ISO_SCRIPT="${REPO_ROOT}/build_files/base/21-container-native-iso.sh"
PACKAGES_TOML="${REPO_ROOT}/build_files/packages/base.toml"
READ_PACKAGES="${REPO_ROOT}/build_files/shared/read-packages"
CONTAINERFILE="${REPO_ROOT}/Containerfile"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/21-container-native-iso.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    BRANDING_DIR="${TEST_ROOT}/branding"
    DRACUT_LOG="${TEST_ROOT}/dracut.log"
    SYSTEMCTL_LOG="${TEST_ROOT}/systemctl.log"

    mkdir -p \
        "${STUB_BIN}" \
        "${BRANDING_DIR}/anaconda" \
        "${TEST_ROOT}/etc/anaconda/profile.d" \
        "${TEST_ROOT}/usr/lib/modules/6.0.0-test" \
        "${TEST_ROOT}/usr/lib/efi/grub2/1/EFI/fedora" \
        "${TEST_ROOT}/usr/lib/efi/shim/1/EFI/fedora" \
        "${TEST_ROOT}/usr/lib/efi/shim/1/EFI/BOOT" \
        "${TEST_ROOT}/usr/share/anaconda/gnome" \
        "${TEST_ROOT}/usr/share/anaconda/post-scripts" \
        "${TEST_ROOT}/usr/share/applications" \
        "${TEST_ROOT}/usr/share/glib-2.0/schemas" \
        "${TEST_ROOT}/usr/share/ublue-os"

    cat >"${TEST_ROOT}/usr/share/ublue-os/image-info.json" <<'EOF'
{
  "image-ref": "ostree-image-signed:docker://ghcr.io/projectbluefin/bluefin",
  "image-tag": "testing"
}
EOF
    cat >"${TEST_ROOT}/usr/lib/os-release" <<'EOF'
VERSION_ID=44
VERSION_CODENAME=Deinonychus
EOF
    touch \
        "${TEST_ROOT}/usr/lib/modules/6.0.0-test/vmlinuz" \
        "${TEST_ROOT}/usr/lib/modules/6.0.0-test/initramfs.img" \
        "${TEST_ROOT}/usr/lib/modules/6.0.0-test/.bluefin-initramfs-done" \
        "${TEST_ROOT}/usr/lib/efi/grub2/1/EFI/fedora/gcdx64.efi" \
        "${TEST_ROOT}/usr/lib/efi/shim/1/EFI/fedora/shimx64.efi" \
        "${TEST_ROOT}/usr/lib/efi/shim/1/EFI/fedora/mmx64.efi" \
        "${TEST_ROOT}/usr/lib/efi/shim/1/EFI/BOOT/BOOTX64.EFI" \
        "${TEST_ROOT}/usr/share/anaconda/interactive-defaults.ks" \
        "${TEST_ROOT}/usr/share/anaconda/gnome/fedora-welcome" \
        "${TEST_ROOT}/usr/share/anaconda/gnome/org.fedoraproject.welcome-screen.desktop" \
        "${TEST_ROOT}/usr/share/applications/liveinst.desktop" \
        "${BRANDING_DIR}/anaconda/bluefin.css"

    cat >"${STUB_BIN}/dracut" <<'EOF'
#!/usr/bin/bash
echo "$*" >"${DRACUT_LOG}"
for arg in "$@"; do
    if [[ "$arg" == */initramfs.img ]]; then
        touch "$arg"
    fi
done
EOF
    cat >"${STUB_BIN}/systemctl" <<'EOF'
#!/usr/bin/bash
echo "$*" >>"${SYSTEMCTL_LOG}"
EOF
    cat >"${STUB_BIN}/glib-compile-schemas" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    cat >"${STUB_BIN}/ghcurl" <<'EOF'
#!/usr/bin/bash
destination=""
url="$1"
while (($#)); do
    case "$1" in
        -o|-Lo)
            destination="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
case "$url" in
    https://ghcr.io/token*)
        echo '{"token":"test-registry-token"}'
        ;;
    *)
        mkdir -p "$(dirname "$destination")"
        printf 'test-key' >"$destination"
        ;;
esac
EOF
    cat >"${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/bash
# Emulates the GHCR manifest HEAD/GET response consumed by
# resolve_stable_digest() in 21-container-native-iso.sh. Tests control the
# behavior via STUB_DIGEST_STATUS (ok|no-digest|fail).
case "${STUB_DIGEST_STATUS:-ok}" in
    ok)
        printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\n\r\n' \
            "${STUB_MANIFEST_DIGEST:-sha256:deadbeef00000000000000000000000000000000000000000000000000feed}"
        ;;
    no-digest)
        printf 'HTTP/1.1 200 OK\r\n\r\n'
        ;;
    fail)
        exit 22
        ;;
esac
EOF
    chmod +x "${STUB_BIN}"/*

    export PATH="${STUB_BIN}:${PATH}"
    export FAKE_ROOT="${TEST_ROOT}"
    export BRANDING_DIR
    export DRACUT_LOG SYSTEMCTL_LOG
    export STUB_DIGEST_STATUS="ok"
    export STUB_MANIFEST_DIGEST="sha256:deadbeef00000000000000000000000000000000000000000000000000feed"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "Stable image embeds the Titanoboa ISO contract and installer configuration" {
    run bash "${ISO_SCRIPT}"
    [ "$status" -eq 0 ]

    run grep -Fx 'label: "titanoboa_boot"' \
        "${TEST_ROOT}/usr/lib/bootc-image-builder/iso.yaml"
    [ "$status" -eq 0 ]
    run grep -F \
        'root=live:CDLABEL=titanoboa_boot enforcing=0 rd.live.image' \
        "${TEST_ROOT}/usr/lib/bootc-image-builder/iso.yaml"
    [ "$status" -eq 0 ]
    run grep -F 'nomodeset' "${TEST_ROOT}/usr/lib/bootc-image-builder/iso.yaml"
    [ "$status" -eq 0 ]

    run grep -F 'profile_id = bluefin' \
        "${TEST_ROOT}/etc/anaconda/profile.d/bluefin.conf"
    [ "$status" -eq 0 ]
    run grep -F \
        "ostreecontainer --url=ghcr.io/projectbluefin/bluefin@${STUB_MANIFEST_DIGEST} --transport=registry" \
        "${TEST_ROOT}/usr/share/anaconda/interactive-defaults.ks"
    [ "$status" -eq 0 ]
    run grep -F \
        "bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ghcr.io/projectbluefin/bluefin@${STUB_MANIFEST_DIGEST}" \
        "${TEST_ROOT}/usr/share/anaconda/post-scripts/install-configure-upgrade.ks"
    [ "$status" -eq 0 ]
    run grep -F 'favorite-apps' \
        "${TEST_ROOT}/usr/lib/bluefin/livesys-session-extra"
    [ "$status" -eq 0 ]
    run grep -Fx \
        'C /var/lib/livesys/livesys-session-extra 0755 root root - /usr/lib/bluefin/livesys-session-extra' \
        "${TEST_ROOT}/usr/lib/tmpfiles.d/bluefin-iso.conf"
    [ "$status" -eq 0 ]
    [ ! -e "${TEST_ROOT}/var/lib/rpm-state" ]

    # /boot must stay empty: content here is masked at runtime and trips
    # `bootc container lint`'s nonempty-boot check in every derived image.
    # See https://github.com/projectbluefin/bluefin/issues/1208.
    [ ! -e "${TEST_ROOT}/boot" ]
    [ ! -f "${DRACUT_LOG}" ]
    [ -f "${TEST_ROOT}/usr/lib/modules/6.0.0-test/.bluefin-initramfs-done" ]
    run grep -F 'enable livesys.service livesys-late.service' \
        "${SYSTEMCTL_LOG}"
    [ "$status" -eq 0 ]
}

@test "Falls back to the mutable :stable tag when the registry manifest lookup fails" {
    export STUB_DIGEST_STATUS="fail"
    run bash "${ISO_SCRIPT}"
    [ "$status" -eq 0 ]

    [[ "$output" == *"::warning::Could not resolve a digest"* ]]
    run grep -F \
        'ostreecontainer --url=ghcr.io/projectbluefin/bluefin:stable --transport=registry' \
        "${TEST_ROOT}/usr/share/anaconda/interactive-defaults.ks"
    [ "$status" -eq 0 ]
    run grep -F \
        'bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ghcr.io/projectbluefin/bluefin:stable' \
        "${TEST_ROOT}/usr/share/anaconda/post-scripts/install-configure-upgrade.ks"
    [ "$status" -eq 0 ]
}

@test "Falls back to the mutable :stable tag when the manifest response has no digest header" {
    export STUB_DIGEST_STATUS="no-digest"
    run bash "${ISO_SCRIPT}"
    [ "$status" -eq 0 ]

    [[ "$output" == *"::warning::Could not resolve a digest"* ]]
    run grep -F \
        'ostreecontainer --url=ghcr.io/projectbluefin/bluefin:stable --transport=registry' \
        "${TEST_ROOT}/usr/share/anaconda/interactive-defaults.ks"
    [ "$status" -eq 0 ]
}

@test "Stable package manifest contains the container-native ISO dependencies" {
    run python3 "${READ_PACKAGES}" "${PACKAGES_TOML}" fedora
    [ "$status" -eq 0 ]

    for package in \
        anaconda-live \
        dracut-live \
        grub2-efi-x64-cdboot \
        isomd5sum \
        libblockdev-btrfs \
        libblockdev-dm \
        libblockdev-lvm \
        libblockdev-mpath \
        livesys-scripts \
        slitherer \
        squashfs-tools \
        xorriso; do
        [[ "$output" == *"$package"* ]]
    done

    run python3 "${READ_PACKAGES}" "${PACKAGES_TOML}" excluded
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\nfirefox\n'* ]]
}

@test "Fails when the ISO builder would have no EFI payload to stage" {
    rm -rf "${TEST_ROOT}/usr/lib/efi"

    run bash "${ISO_SCRIPT}"
    [ "$status" -ne 0 ]
    [[ "$output" == *'No EFI payload found under /usr/lib/efi'* ]]
}

@test "Containerfile runs the ISO contract script after Stage 2 under a boot tmpfs" {
    run python3 -c '
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
start = next(
    index for index, line in enumerate(lines)
    if "source=/build_files/base/21-container-native-iso.sh" in line
)
end = next(
    index for index in range(start + 1, len(lines))
    if lines[index].strip() == "'\''"
)
print("\n".join(lines[start:end + 1]))
' "${CONTAINERFILE}"
    [ "$status" -eq 0 ]
    [[ "$output" == *'/ctx/build_files/base/21-container-native-iso.sh'* ]]
    [[ "$output" == *'tmpfs,dst=/boot'* ]]

    # No --skip: derived images run the default lint, so this one must too.
    run grep -Fx \
        'RUN bootc container lint --fatal-warnings' \
        "${CONTAINERFILE}"
    [ "$status" -eq 0 ]
    [[ "$output" != *'var-tmpfiles'* ]]

    run grep -F 'nonempty-boot' "${CONTAINERFILE}"
    [ "$status" -ne 0 ]
}
