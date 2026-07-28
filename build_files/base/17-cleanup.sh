#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Setup Systemd
# systemctl --global enable bazaar.service
systemctl --global enable podman-auto-update.timer
systemctl --global enable ublue-user-setup.service
systemctl enable brew-setup.service
systemctl enable dconf-update.service
systemctl enable flatpak-nuke-fedora.service
systemctl enable input-remapper.service
systemctl enable rpm-ostree-countme.service
systemctl enable tailscaled.service
systemctl enable ublue-system-setup.service

systemctl enable flatpak-preinstall.service

# Onboard to bootc unified storage on first boot (experimental — enables zstd:chunked partial pulls)
systemctl enable bootc-unified-storage.service

# Updater
systemctl enable uupd.timer

# Refresh community stats (user count, Bazaar downloads) for fastfetch
systemctl enable bluefin-stats-refresh.timer

#disable the old rpm-ostreed-automatic.timer
systemctl disable rpm-ostreed-automatic.timer

# Hide Desktop Files. Hidden removes mime associations
for file in fish htop nvtop; do
    if [[ -f "/usr/share/applications/$file.desktop" ]]; then
        sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/"$file".desktop
    fi
done

#Add the Flathub Flatpak remote and remove the Fedora Flatpak remote
flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
systemctl disable flatpak-add-fedora-repos.service

# NOTE: With isolated COPR installation, most repos are never enabled globally.
# We only need to clean up repos that were enabled during the build process.

# shellcheck source=build_files/shared/disable-repos.sh
source /ctx/build_files/shared/disable-repos.sh
disable_third_party_repos

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
