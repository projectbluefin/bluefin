#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -euo pipefail

ROOT="${FAKE_ROOT:-}"
IMAGE_INFO="${ROOT}/usr/share/ublue-os/image-info.json"
ISO_CONFIG="${ROOT}/usr/lib/bootc-image-builder/iso.yaml"
SBKEY_URL="https://github.com/ublue-os/akmods/raw/main/certs/public_key.der"

IMAGE_TAG="$(jq -r '."image-tag"' "${IMAGE_INFO}")"
IMAGE_REF="$(jq -r '."image-ref"' "${IMAGE_INFO}")"
IMAGE_REF="${IMAGE_REF##*://}"

mkdir -p \
    "${ROOT}/boot/efi/EFI" \
    "${ROOT}/etc/anaconda/profile.d" \
    "${ROOT}/etc/sysconfig" \
    "${ROOT}/usr/lib/bootc-image-builder" \
    "${ROOT}/usr/share/anaconda/pixmaps/silverblue" \
    "${ROOT}/usr/share/anaconda/post-scripts" \
    "${ROOT}/var/lib/livesys" \
    "${ROOT}/var/lib/rpm-state"

cat >"${ROOT}/etc/anaconda/profile.d/bluefin.conf" <<'EOF'
# Anaconda configuration file for Bluefin

[Profile]
profile_id = bluefin

[Profile Detection]
os_id = bluefin

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1
default_partitioning =
    /     (min 1 GiB, max 70 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var  (btrfs)

[User Interface]
custom_stylesheet = /usr/share/anaconda/pixmaps/silverblue/fedora-silverblue.css
webui_web_engine = slitherer
hidden_spokes =
    NetworkSpoke
    PasswordSpoke
    UserSpoke
hidden_webui_pages =
    anaconda-screen-accounts

[Localization]
use_geolocation = False
EOF

# shellcheck source=/dev/null
source "${ROOT}/usr/lib/os-release"
echo "Bluefin release ${VERSION_ID} (${VERSION_CODENAME})" >"${ROOT}/etc/system-release"
sed -i 's/ANACONDA_PRODUCTVERSION=.*/ANACONDA_PRODUCTVERSION=""/' \
    "${ROOT}"/usr/{,s}bin/liveinst 2>/dev/null || true
sed -i 's|^Icon=.*|Icon=/usr/share/pixmaps/fedora-logo-icon.png|' \
    "${ROOT}/usr/share/applications/liveinst.desktop" 2>/dev/null || true
sed -i 's| Fedora| Bluefin|' \
    "${ROOT}/usr/share/anaconda/gnome/fedora-welcome" 2>/dev/null || true
sed -i 's|Activities|in the dock|' \
    "${ROOT}/usr/share/anaconda/gnome/fedora-welcome" 2>/dev/null || true
sed -i -e 's/Fedora/Bluefin/g' -e 's/CentOS/Bluefin/g' \
    "${ROOT}/usr/share/anaconda/gnome/org.fedoraproject.welcome-screen.desktop" \
    2>/dev/null || true

cleanup_branding=0
if [[ -z "${BRANDING_DIR:-}" ]]; then
    BRANDING_DIR="${ROOT}/var/cache/bluefin-iso-branding"
    cleanup_branding=1
    rm -rf "${BRANDING_DIR}"
    mkdir -p "${BRANDING_DIR}"
    ghcurl "https://api.github.com/repos/projectbluefin/branding/tarball" --retry 3 |
        tar -xz --strip-components=1 -C "${BRANDING_DIR}"
fi
cp -a "${BRANDING_DIR}/anaconda/." \
    "${ROOT}/usr/share/anaconda/pixmaps/silverblue/"
if ((cleanup_branding)); then
    rm -rf "${BRANDING_DIR}"
fi

# Current Titanoboa embeds the source rootfs but does not seed its container
# storage, so the Anaconda payload must be pulled from the registry.
cat >>"${ROOT}/usr/share/anaconda/interactive-defaults.ks" <<EOF
ostreecontainer --url=${IMAGE_REF}:${IMAGE_TAG} --transport=registry --no-signature-verification
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%include /usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
EOF

cat >"${ROOT}/usr/share/anaconda/post-scripts/install-configure-upgrade.ks" <<EOF
%post --erroronfail
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ${IMAGE_REF}:${IMAGE_TAG}
%end
EOF

cat >"${ROOT}/usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks" <<'EOF'
%post --erroronfail
systemctl disable flatpak-add-fedora-repos.service
%end
EOF

cat >"${ROOT}/usr/share/anaconda/post-scripts/install-flatpaks.ks" <<'EOF'
%post --erroronfail --nochroot
deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0)"
target="/mnt/sysimage/ostree/deploy/default/deploy/$deployment.0/var/lib/"
mkdir -p "$target"
rsync -aAXUHKP --filter='-x security.selinux' /var/lib/flatpak "$target"
%end
EOF

ghcurl "${SBKEY_URL}" --retry 15 -o "${ROOT}/etc/sb_pubkey.der"
cat >"${ROOT}/usr/share/anaconda/post-scripts/secureboot-enroll-key.ks" <<'EOF'
%post --erroronfail --nochroot
set -oue pipefail

readonly ENROLLMENT_PASSWORD="universalblue"
readonly SECUREBOOT_KEY="/etc/sb_pubkey.der"

if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "EFI mode not detected. Skipping key enrollment."
    exit 0
fi

if [[ ! -f "$SECUREBOOT_KEY" ]]; then
    echo "Secure boot key not provided: $SECUREBOOT_KEY"
    exit 0
fi

SYS_ID="$(cat /sys/devices/virtual/dmi/id/product_name)"
if [[ ":Jupiter:Galileo:" =~ ":$SYS_ID:" ]]; then
    echo "Steam Deck hardware detected. Skipping key enrollment."
    exit 0
fi

mokutil --timeout -1 || :
echo -e "$ENROLLMENT_PASSWORD\n$ENROLLMENT_PASSWORD" | mokutil --import "$SECUREBOOT_KEY" || :
%end
EOF

# livesys-gnome already disables GNOME Software autostart/search in live boots.
# Keep only Bluefin-specific live changes in its conditional extension hook.
cat >"${ROOT}/var/lib/livesys/livesys-session-extra" <<'EOF'
cat >/usr/share/glib-2.0/schemas/zz2-org.gnome.shell.gschema.override <<'SCHEMA'
[org.gnome.shell]
welcome-dialog-last-shown-version='4294967295'
favorite-apps = ['anaconda.desktop', 'documentation.desktop', 'discourse.desktop', 'org.mozilla.firefox.desktop', 'org.gnome.Nautilus.desktop']
SCHEMA

cat >/usr/share/glib-2.0/schemas/zz3-bluefin-installer-power.gschema.override <<'SCHEMA'
[org.gnome.settings-daemon.plugins.power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0

[org.gnome.desktop.session]
idle-delay=uint32 0
SCHEMA

glib-compile-schemas /usr/share/glib-2.0/schemas

for unit in \
    rpm-ostree-countme.service \
    tailscaled.service \
    bootloader-update.service \
    brew-upgrade.timer \
    brew-update.timer \
    brew-setup.service \
    rpm-ostreed-automatic.timer \
    uupd.timer \
    ublue-system-setup.service \
    flatpak-preinstall.service; do
    systemctl --no-reload disable "$unit" 2>/dev/null || :
    systemctl stop "$unit" 2>/dev/null || :
done

for unit in podman-auto-update.timer ublue-user-setup.service; do
    systemctl --global disable "$unit" 2>/dev/null || :
done
EOF
chmod 0755 "${ROOT}/var/lib/livesys/livesys-session-extra"

echo 'livesys_session=gnome' >"${ROOT}/etc/sysconfig/livesys"
systemctl enable livesys.service livesys-late.service

shopt -s nullglob
kernel_dirs=("${ROOT}"/usr/lib/modules/*)
if ((${#kernel_dirs[@]} != 1)); then
    echo "Expected exactly one kernel under /usr/lib/modules, found ${#kernel_dirs[@]}" >&2
    exit 1
fi
kernel_dir="${kernel_dirs[0]}"
kernel="$(basename "${kernel_dir}")"
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
    --add "ostree dmsquash-live dmsquash-live-autooverlay" \
    "${kernel_dir}/initramfs.img" "${kernel}"
chmod 0600 "${kernel_dir}/initramfs.img"
touch "${kernel_dir}/.bluefin-initramfs-done"

efi_dirs=("${ROOT}"/usr/lib/efi/*/*/EFI)
if ((${#efi_dirs[@]} == 0)); then
    echo "No EFI payload found under /usr/lib/efi" >&2
    exit 1
fi
for efi_dir in "${efi_dirs[@]}"; do
    cp -a "${efi_dir}/." "${ROOT}/boot/efi/EFI/"
done

cat >"${ISO_CONFIG}" <<'EOF'
label: "titanoboa_boot"
grub2:
  default: 0
  timeout: 10
  entries:
    - name: "Bluefin Live ISO"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=titanoboa_boot enforcing=0 rd.live.image"
      initrd: "/images/pxeboot/initrd.img"
    - name: "Bluefin Live ISO (Basic Graphics)"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=titanoboa_boot enforcing=0 rd.live.image nomodeset"
      initrd: "/images/pxeboot/initrd.img"
EOF

echo "::endgroup::"
