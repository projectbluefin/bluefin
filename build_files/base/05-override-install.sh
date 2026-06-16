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
mkdir -p /usr/lib/systemd/system-generators
ghcurl "https://raw.githubusercontent.com/coreos/fedora-coreos-config/refs/heads/stable/overlay.d/05core/usr/lib/systemd/system-generators/coreos-sulogin-force-generator" --retry 3 -Lo /usr/lib/systemd/system-generators/coreos-sulogin-force-generator
chmod +x /usr/lib/systemd/system-generators/coreos-sulogin-force-generator

# Configure firewalld with Fedora Workstation defaults
# https://src.fedoraproject.org/rpms/firewalld/blob/rawhide/f/firewalld.spec
ghcurl "https://src.fedoraproject.org/rpms/firewalld/raw/rawhide/f/FedoraWorkstation.xml" --retry 3 -Lo /usr/lib/firewalld/zones/FedoraWorkstation.xml
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
