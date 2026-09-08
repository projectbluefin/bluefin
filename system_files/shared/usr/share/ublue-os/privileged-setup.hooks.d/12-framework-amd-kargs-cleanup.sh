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
#
# NOTE (bluefin#1126): version-script records a migration as "complete" the
# moment it is called, before this script's body runs. A naive
# `version-script ... || exit 0` guard at the top would mark the migration
# done even if rpm-ostree is unavailable or the karg deletion fails, so a
# failed attempt would never be retried on a later boot. To stay
# retry-safe, completion is tracked with our own on-disk marker that is
# only written after the migration has actually succeeded (or has been
# determined not to apply), and version-script is invoked afterwards purely
# to keep the shared setup-versioning ledger in sync.

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

STATE_FILE="/var/lib/ublue-os/.framework-amd-kargs-cleanup-v1"

[[ -e "${STATE_FILE}" ]] && exit 0

set -euo pipefail

VENDOR_PATH="/sys/devices/virtual/dmi/id/chassis_vendor"
PRODUCT_PATH="/sys/devices/virtual/dmi/id/product_name"
STALE_KARG="module_blacklist=hid_sensor_hub"

mark_done() {
    mkdir -p "$(dirname "${STATE_FILE}")"
    touch "${STATE_FILE}"
    version-script framework-amd-kargs-cleanup privileged 1 || true
}

if [[ ! -r "${VENDOR_PATH}" || ! -r "${PRODUCT_PATH}" ]]; then
    echo "Framework AMD kargs cleanup: DMI information not available, skipping."
    exit 0
fi

vendor="$(<"${VENDOR_PATH}")"
product_name="$(<"${PRODUCT_PATH}")"

# Only run on Framework hardware. Non-Framework vendor is a permanent
# condition, so it's safe to record completion.
if [[ "${vendor}" != "Framework" ]]; then
    mark_done
    exit 0
fi

# Positive AMD match: only act on Framework laptops that name AMD in the product
# string.  This avoids mutating boot config on Intel or future unknown Framework
# hardware. Also a permanent condition, safe to record completion.
if [[ ! "${product_name}" =~ AMD ]]; then
    mark_done
    exit 0
fi

if ! command -v rpm-ostree >/dev/null 2>&1; then
    echo "Warning: rpm-ostree not found; unable to clean up stale AMD Framework kargs."
    exit 0
fi

if ! current_kargs="$(rpm-ostree kargs)"; then
    echo "Failed to query kernel arguments; will retry on next boot." >&2
    exit 1
fi

if ! grep -Fq "${STALE_KARG}" <<< "${current_kargs}"; then
    echo "AMD Framework: ${STALE_KARG} not present — nothing to do."
    mark_done
    exit 0
fi

if rpm-ostree kargs --delete="${STALE_KARG}"; then
    echo "Removed stale AMD Framework karg: ${STALE_KARG}. Reboot to activate."
    mark_done
else
    echo "Failed to remove stale AMD Framework karg; will retry on next boot." >&2
    exit 1
fi
