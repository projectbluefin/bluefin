#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -oue pipefail

KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
INITRAMFS_MARKER="/lib/modules/${QUALIFIED_KERNEL}/.bluefin-initramfs-done"

# Stage 1 (04-install-kernel-akmods.sh) runs dracut and touches the marker.
# Skip here when the marker is present and FORCE_INITRAMFS is not set,
# saving 2–6 min on system_files-only rebuilds where Stage 1 is cached.
if [[ "${FORCE_INITRAMFS:-0}" != "1" ]] && [[ -f "${INITRAMFS_MARKER}" ]]; then
    echo "Initramfs already built for ${QUALIFIED_KERNEL} — skipping dracut (Stage 1 marker present)"
    echo "::endgroup::"
    exit 0
fi

echo "Regenerating initramfs for ${QUALIFIED_KERNEL}"
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible \
    -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
touch "${INITRAMFS_MARKER}"

echo "::endgroup::"
