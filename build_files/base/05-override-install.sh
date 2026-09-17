#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# We do not need anything here at all
rm -rf /usr/src
rm -rf /usr/share/doc
# Remove kernel-devel from rpmdb because all package files are removed from /usr/src
rpm --erase --nodeps kernel-devel

mkdir -p /usr/share/doc/bluefin
# Offline Bluefin documentation
ghcurl "https://github.com/projectbluefin/documentation/releases/download/0.1/bluefin.pdf" --retry 3 -o /tmp/bluefin.pdf
install -Dm0644 -t /usr/share/doc/bluefin/ /tmp/bluefin.pdf
# Tag for rechunker — large unpackaged file gets its own layer
setfattr -n user.component -v bluefin-docs /usr/share/doc/bluefin/bluefin.pdf

# Footgun, See: https://github.com/ublue-os/main/issues/598
rm -f /usr/bin/chsh /usr/bin/lchsh

# Add linuxbrew to the list of paths usable by `sudo`
# not a sudoers.d override because we want to get updates from upstream and not break everything
sed -Ei "s/secure_path = (.*)/secure_path = \1:\/home\/linuxbrew\/.linuxbrew\/bin/" /etc/sudoers

# https://github.com/ublue-os/main/pull/334
ln -s "/usr/share/fonts/google-noto-sans-cjk-fonts" "/usr/share/fonts/noto-cjk"

# use CoreOS' generator for emergency/rescue boot
# see detail: https://github.com/ublue-os/main/issues/653
# Pinned to commit SHA + SHA-256 digest to prevent unverified root-at-boot execution (CWE-829 / CWE-494)
COREOS_SULOGIN_COMMIT="682c839aabbc01564f1605bb41687a7511180031"
COREOS_SULOGIN_SHA256="eb9222214c4647f1ed430f379dca13c3ba945a6aa7950ce6b2d5be3e0a337da1"
mkdir -p /usr/lib/systemd/system-generators
ghcurl "https://raw.githubusercontent.com/coreos/fedora-coreos-config/${COREOS_SULOGIN_COMMIT}/overlay.d/05core/usr/lib/systemd/system-generators/coreos-sulogin-force-generator" --retry 3 -Lo /usr/lib/systemd/system-generators/coreos-sulogin-force-generator
echo "${COREOS_SULOGIN_SHA256}  /usr/lib/systemd/system-generators/coreos-sulogin-force-generator" | sha256sum -c -
chmod +x /usr/lib/systemd/system-generators/coreos-sulogin-force-generator

# Configure firewalld with Fedora Workstation defaults
# https://src.fedoraproject.org/rpms/firewalld/blob/rawhide/f/firewalld.spec
# Pinned to commit SHA + SHA-256 digest for deterministic and tamper-resistant firewall configuration
FIREWALLD_COMMIT="4c18519ae432381e9cb18e105f0f15c46537e81c"
FIREWALLD_ZONE_SHA256="ceb2a036759ae52b623e2d50f2d6056e698ff6ce0763cfd76ef3f6a259b1a14e"
ghcurl "https://src.fedoraproject.org/rpms/firewalld/raw/${FIREWALLD_COMMIT}/f/FedoraWorkstation.xml" --retry 3 -Lo /usr/lib/firewalld/zones/FedoraWorkstation.xml
echo "${FIREWALLD_ZONE_SHA256}  /usr/lib/firewalld/zones/FedoraWorkstation.xml" | sha256sum -c -
grep -F -e '<port protocol="udp" port="1025-65535"/>' /usr/lib/firewalld/zones/FedoraWorkstation.xml
sed -i 's|^DefaultZone=.*|DefaultZone=FedoraWorkstation|g' /etc/firewalld/firewalld.conf
sed -i 's|^IPv6_rpfilter=.*|IPv6_rpfilter=loose|g' /etc/firewalld/firewalld.conf

# Add Mutter experimental-features
# NOTE: The gschema override file lives in system_files/ and is only overlaid
# in Stage 2 (build-gnome-extensions.sh handles compilation). This block was
# moved to 00-image-info.sh which runs after the Stage 2 system_files rsync.

# Rebuild gdk-pixbuf loader cache so all installed loaders are registered
gdk-pixbuf-query-loaders-64 --update-cache

echo "::endgroup::"
