#!/usr/bin/bash
# Applies usbcore.autosuspend=-1 on Framework laptops with Intel Core Ultra
# silicon. These machines hit a ucsi_acpi USBC000 failure on s2idle resume
# ("possible UCSI driver bug", "failed to re-enable notifications"), which has
# been observed escalating into a resume hang (bluefin#231). Pinning USB
# autosuspend off reduces the USB-C power state churn that triggers it while
# the upstream kernel fix is tracked.
#
# NOTE (bluefin#1126): version-script records a migration as "complete" the
# moment it is called, before this script's body runs. A naive
# `version-script ... || exit 0` guard at the top would mark the workaround
# done even if rpm-ostree is unavailable or appending the karg fails, so an
# affected laptop that failed once would never retry and would silently keep
# the resume bug. To stay retry-safe, completion is tracked with our own
# on-disk marker that is only written after the karg has actually been applied
# (or has been determined not to apply), and version-script is invoked
# afterwards purely to keep the shared setup-versioning ledger in sync.

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

STATE_FILE="/var/lib/ublue-os/.framework-ucsi-workaround-v1"

[[ -e "${STATE_FILE}" ]] && exit 0

set -euo pipefail

VENDOR_PATH="/sys/devices/virtual/dmi/id/chassis_vendor"
PRODUCT_PATH="/sys/devices/virtual/dmi/id/product_name"
WORKAROUND_KARG="usbcore.autosuspend=-1"

mark_done() {
    mkdir -p "$(dirname "${STATE_FILE}")"
    touch "${STATE_FILE}"
    version-script framework-ucsi-workaround privileged 1 || true
}

# DMI may not be readable yet this boot; that is transient, so do not record
# completion — the next boot retries.
if [[ ! -r "${VENDOR_PATH}" || ! -r "${PRODUCT_PATH}" ]]; then
    echo "Framework UCSI workaround skipped: DMI information not available."
    exit 0
fi

vendor="$(<"${VENDOR_PATH}")"
product_name="$(<"${PRODUCT_PATH}")"

# Non-Framework hardware is a permanent condition, so it is safe to record
# completion and stop checking on every boot.
if [[ "${vendor}" != "Framework" ]]; then
    mark_done
    exit 0
fi

# Only Intel Core Ultra Framework laptops are affected. Also permanent.
if [[ ! "${product_name}" =~ Intel\ Core\ Ultra ]]; then
    mark_done
    exit 0
fi

if ! command -v rpm-ostree >/dev/null 2>&1; then
    echo "Warning: rpm-ostree not found; will retry Framework UCSI workaround on next boot." >&2
    exit 0
fi

if rpm-ostree kargs | grep -Fq "${WORKAROUND_KARG}"; then
    echo "Framework UCSI workaround already configured: ${WORKAROUND_KARG}"
    mark_done
    exit 0
fi

if rpm-ostree kargs --append-if-missing="${WORKAROUND_KARG}"; then
    echo "Applied Framework UCSI workaround (${WORKAROUND_KARG}). Reboot to activate."
    mark_done
else
    echo "Failed to apply Framework UCSI workaround; will retry on next boot." >&2
    exit 1
fi
