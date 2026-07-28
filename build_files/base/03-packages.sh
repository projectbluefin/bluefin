#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# All DNF-related operations should be done here whenever possible

# shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh
# shellcheck source=build_files/shared/package-lib.sh
source /ctx/build_files/shared/package-lib.sh

READ_PKGS="python3 /ctx/build_files/shared/read-packages"
PKGS_TOML="/ctx/build_files/packages/base.toml"

# use negativo17 for 3rd party packages with higher priority than default
# mitigate upstream packaging bug: https://bugzilla.redhat.com/show_bug.cgi?id=2332429
# swap the incorrectly installed OpenCL-ICD-Loader for ocl-icd, the expected package
# TODO: remove me when F42 dropped, F43 is not affected
if [[ "$(rpm -E %fedora)" == "42" ]]; then
    dnf5 -y swap --repo='fedora' \
        OpenCL-ICD-Loader ocl-icd
fi

if ! grep -q fedora-multimedia <(dnf5 repolist); then
    # Enable or Install Repofile
    dnf5 config-manager setopt fedora-multimedia.enabled=1 ||
        dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"
fi
# Set higher priority
dnf5 config-manager setopt fedora-multimedia.priority=90

# use override to replace mesa and others with less crippled versions
readarray -t OVERRIDES < <($READ_PKGS "$PKGS_TOML" multimedia_overrides)
dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

# NOTE:
# Packages are split into FEDORA_PACKAGES and COPR_PACKAGES to prevent
# malicious COPRs from injecting fake versions of Fedora packages.
# Fedora packages are installed first in bulk (safe).
# COPR packages are installed individually with isolated enablement.

# Base packages from Fedora repos — common to all versions
readarray -t FEDORA_PACKAGES < <($READ_PKGS "$PKGS_TOML" fedora)

# Version-specific additions
readarray -t _ver_pkgs < <($READ_PKGS "$PKGS_TOML" "fedora_v${FEDORA_MAJOR_VERSION}" 2>/dev/null || true)
FEDORA_PACKAGES+=("${_ver_pkgs[@]}")

# Install Fedora, Tailscale, and multimedia packages together while keeping COPR packages isolated.
echo "Installing ${#FEDORA_PACKAGES[@]} Fedora packages plus Tailscale and multimedia packages..."
dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 config-manager setopt tailscale-stable.enabled=0
dnf5 -y install \
    --enablerepo='tailscale-stable' \
    --enablerepo='fedora-multimedia' \
    -x PackageKit* \
    "${FEDORA_PACKAGES[@]}" \
    tailscale \
    ffmpeg{,-libs} libavcodec @multimedia gstreamer1-plugins-{bad-free,bad-free-libs,good,base} lame{,-libs} libfdk-aac libjxl ffmpegthumbnailer

# From ublue-os/packages
copr_install_isolated "ublue-os/packages" \
    "uupd"

# Packages to exclude — conflicts with or replaced by image content
# shellcheck disable=SC2034  # passed by name to remove_excluded_packages
readarray -t EXCLUDED_PACKAGES < <($READ_PKGS "$PKGS_TOML" excluded)
remove_excluded_packages EXCLUDED_PACKAGES

## Pins and Overrides
## Use this section to pin packages in order to avoid regressions
# Remember to leave a note with rationale/link to issue for each pin!
#
# Example:
#if [ "$FEDORA_MAJOR_VERSION" -eq "41" ]; then
#    Workaround pkcs11-provider regression, see issue #1943
#    rpm-ostree override replace https://bodhi.fedoraproject.org/updates/FEDORA-2024-dd2e9fb225
#fi

echo "::endgroup::"
