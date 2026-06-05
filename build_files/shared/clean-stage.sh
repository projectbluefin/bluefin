#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# CLEAN_ROOT: filesystem prefix applied to all paths.
# Empty (the production default) means the actual root.
# Set to a temp directory during unit tests.
CLEAN_ROOT="${CLEAN_ROOT:-}"

# Revert back to upstream defaults
dnf5 config-manager setopt keepcache=0
dnf5 versionlock clear

# This comes last because we can't *ever* afford to ship fedora flatpaks on the image
systemctl disable flatpak-add-fedora-repos.service
systemctl mask flatpak-add-fedora-repos.service
rm -f "${CLEAN_ROOT}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"

rm -rf "${CLEAN_ROOT}/.gitkeep"
find "${CLEAN_ROOT}/var"/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find "${CLEAN_ROOT}/var/cache"/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
rm -rf "${CLEAN_ROOT}/tmp" && mkdir -p "${CLEAN_ROOT}/tmp"
# shellcheck disable=SC2114
rm -rf "${CLEAN_ROOT}/boot" && mkdir -p "${CLEAN_ROOT}/boot"
# Clear /run — dnf5 and SELinux policy tooling leave artifacts here during build.
# /run is a tmpfs at runtime; anything baked into the image is junk and will
# trip bootc container lint's nonempty-run-tmp check.
rm -rf "${CLEAN_ROOT}/run" && mkdir -p "${CLEAN_ROOT}/run"

echo "::endgroup::"
