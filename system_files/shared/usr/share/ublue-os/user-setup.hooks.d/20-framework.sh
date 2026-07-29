#!/usr/bin/bash
# Per-vendor user setup for Framework laptops.
# Installs the Framework EC tool via Homebrew for hardware management.

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script 20-framework user 1 || exit 0

set -euo pipefail

CHASSIS_VENDOR_PATH="/sys/devices/virtual/dmi/id/chassis_vendor"
BREW_PREFIX="/home/linuxbrew/.linuxbrew"

# Only run on Framework hardware
[[ -r "${CHASSIS_VENDOR_PATH}" ]] || exit 0
chassis_vendor="$(cat "${CHASSIS_VENDOR_PATH}")"
[[ "${chassis_vendor}" == "Framework" ]] || exit 0

echo "Framework laptop detected — running Framework-specific user setup"

# Guard: brew must be available
if ! command -v brew >/dev/null 2>&1; then
    echo "Warning: brew not found — skipping Framework setup"
    exit 0
fi

# Guard: user must have write access to the Homebrew prefix
if [[ ! -w "${BREW_PREFIX}" ]]; then
    echo "Warning: user lacks write permission to ${BREW_PREFIX} — skipping Framework setup"
    exit 0
fi

# Install a package only when it is not already present
install_if_missing() {
    local pkg="$1"
    if brew list "${pkg}" >/dev/null 2>&1; then
        echo "${pkg} already installed, skipping"
    else
        echo "Installing ${pkg}..."
        brew install "${pkg}"
    fi
}

# Framework EC tool for hardware management (fan curves, battery charge limit, etc.)
install_if_missing "fw-ectool"
