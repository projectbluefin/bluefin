#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Existing bluefin systems have bling.sh and bling.fish in their default
# locations. Copy to bluefin-cli so upgrades find them in the new path.
mkdir -p /usr/share/ublue-os/bluefin-cli
cp /usr/share/ublue-os/bling/* /usr/share/ublue-os/bluefin-cli

# Remove just docs that are not needed in the image
rm -rf /usr/share/doc/just/README.*.md

echo "::endgroup::"

# Remove orphan /usr/lib/modules/ directories left by kernel-tools version bumps
# that don't bring the matching kernel-core. akmods-ostree-post iterates all
# /usr/lib/modules/ entries and fails on those with no matching kernel headers.
for kver_dir in /usr/lib/modules/*/; do
    kver=$(basename "${kver_dir}")
    if ! rpm -q "kernel-core-${kver}" &>/dev/null; then
        echo "Removing orphan /usr/lib/modules/${kver} (no matching kernel-core RPM)"
        rm -rf "${kver_dir}"
    fi
done
