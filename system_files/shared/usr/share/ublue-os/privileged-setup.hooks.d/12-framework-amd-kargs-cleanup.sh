#!/usr/bin/bash
# Removes the stale module_blacklist=hid_sensor_hub kernel argument from
# AMD Framework laptops. This karg was set by an older image version that
# incorrectly applied an Intel-specific rule to all Framework hardware.
# On AMD Framework systems this module has no known purpose on the blacklist
# and may suppress unrelated USB HID sensor functionality.
#
# This is a one-time migration cleanup. The kernel driver fix for battery
# charge threshold control on AMD Framework is in fw-charge-control.conf
# (bluefin#879); this script only removes a stale karg side-effect.

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script framework-amd-kargs-cleanup privileged 1 || exit 0

set -euo pipefail

VENDOR_PATH="/sys/devices/virtual/dmi/id/chassis_vendor"
PRODUCT_PATH="/sys/devices/virtual/dmi/id/product_name"
STALE_KARG="module_blacklist=hid_sensor_hub"

if [[ ! -r "${VENDOR_PATH}" || ! -r "${PRODUCT_PATH}" ]]; then
    echo "Framework AMD kargs cleanup: DMI information not available, skipping."
    exit 0
fi

vendor="$(<"${VENDOR_PATH}")"
product_name="$(<"${PRODUCT_PATH}")"

# Only run on Framework hardware
[[ "${vendor}" == "Framework" ]] || exit 0

# Positive AMD match: only act on Framework laptops that name AMD in the product
# string.  This avoids mutating boot config on Intel or future unknown Framework
# hardware.
[[ "${product_name}" =~ AMD ]] || exit 0

if ! command -v rpm-ostree >/dev/null 2>&1; then
    echo "Warning: rpm-ostree not found; unable to clean up stale AMD Framework kargs."
    exit 0
fi

if ! rpm-ostree kargs | grep -Fq "${STALE_KARG}"; then
    echo "AMD Framework: ${STALE_KARG} not present — nothing to do."
    exit 0
fi

rpm-ostree kargs --delete="${STALE_KARG}"
echo "Removed stale AMD Framework karg: ${STALE_KARG}. Reboot to activate."

