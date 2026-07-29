#!/usr/bin/bash

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script framework-ucsi-workaround privileged 1 || exit 0

set -euo pipefail

VENDOR_PATH="/sys/devices/virtual/dmi/id/chassis_vendor"
PRODUCT_PATH="/sys/devices/virtual/dmi/id/product_name"
WORKAROUND_KARG="usbcore.autosuspend=-1"

if [[ ! -r "${VENDOR_PATH}" || ! -r "${PRODUCT_PATH}" ]]; then
    echo "Framework UCSI workaround skipped: DMI information not available."
    exit 0
fi

vendor="$(<"${VENDOR_PATH}")"
product_name="$(<"${PRODUCT_PATH}")"

if [[ "${vendor}" != "Framework" ]]; then
    exit 0
fi

if [[ ! "${product_name}" =~ Intel\ Core\ Ultra ]]; then
    exit 0
fi

if ! command -v rpm-ostree >/dev/null 2>&1; then
    echo "Warning: rpm-ostree not found; unable to apply Framework UCSI workaround."
    exit 0
fi

if rpm-ostree kargs | grep -Fq "${WORKAROUND_KARG}"; then
    echo "Framework UCSI workaround already configured: ${WORKAROUND_KARG}"
    exit 0
fi

rpm-ostree kargs --append-if-missing="${WORKAROUND_KARG}"
echo "Applied Framework UCSI workaround (${WORKAROUND_KARG}). Reboot to activate."
