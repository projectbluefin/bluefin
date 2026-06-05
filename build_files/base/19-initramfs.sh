#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -oue pipefail

# Sealed images bundle the initramfs inside the UKI — skip the manual dracut rebuild.
if [[ "${SEALED:-}" == "1" ]]; then
    echo "Sealed build: skipping initramfs rebuild (UKI owns the boot chain)"
else
    KERNEL_SUFFIX=""
    QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
    export DRACUT_NO_XATTR=1
    /usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
    chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
fi

echo "::endgroup::"
