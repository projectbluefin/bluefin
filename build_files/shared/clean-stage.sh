#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Revert back to upstream defaults
dnf5 config-manager setopt keepcache=0
dnf5 versionlock clear

# This comes last because we can't *ever* afford to ship fedora flatpaks on the image
systemctl disable flatpak-add-fedora-repos.service
systemctl mask flatpak-add-fedora-repos.service
rm -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service

rm -rf /.gitkeep
find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
rm -rf /tmp && mkdir -p /tmp
# shellcheck disable=SC2114
rm -rf /boot && mkdir -p /boot
# Clear /run — dnf5 and SELinux policy tooling leave artifacts here during build.
# /run is a tmpfs at runtime; anything baked into the image is junk and will
# trip bootc container lint's nonempty-run-tmp check.
rm -rf /run && mkdir -p /run

echo "::endgroup::"
