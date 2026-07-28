#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Beta Updates Testing Repo...
if [[ "${UBLUE_IMAGE_TAG}" == "beta" ]]; then
    dnf5 config-manager setopt updates-testing.enabled=1
fi

# Remove Existing Kernel
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    rpm --erase $pkg --nodeps
done

# Fetch Common AKMODS & Kernel RPMS
# Pull large OCI artifacts in parallel before any RPM installs.
declare -A PULL_PIDS

skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods:"${AKMODS_FLAVOR}"-"$(rpm -E %fedora)"-"${KERNEL}" dir:/tmp/akmods &
PULL_PIDS[akmods]=$!

if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    mkdir -p /tmp/akmods-rpms
    skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods-nvidia-open:"${AKMODS_FLAVOR}"-"$(rpm -E %fedora)"-"${KERNEL}" dir:/tmp/akmods-rpms &
    PULL_PIDS[nvidia]=$!
fi

if [[ "${AKMODS_FLAVOR}" =~ coreos ]]; then
    mkdir -p /tmp/akmods-zfs
    skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods-zfs:"${AKMODS_FLAVOR}"-"$(rpm -E %fedora)"-"${KERNEL}" dir:/tmp/akmods-zfs &
    PULL_PIDS[zfs]=$!
fi

for key in "${!PULL_PIDS[@]}"; do
    if ! wait "${PULL_PIDS[$key]}"; then
        echo "ERROR: Failed to pull ${key} image" >&2
        exit 1
    fi
done
echo "All image pulls completed successfully"

AKMODS_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods/manifest.json | cut -d : -f 2)
tar -xvzf /tmp/akmods/"$AKMODS_TARGZ" -C /tmp/
mv /tmp/rpms/* /tmp/akmods/
# NOTE: kernel-rpms should auto-extract into correct location

# Install Kernel
dnf5 -y install \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

# TODO: Figure out why akmods cache is pulling in akmods/kernel-devel
dnf5 -y install \
    /tmp/kernel-rpms/kernel-devel-*.rpm

dnf5 versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra

dnf5 copr enable -y ublue-os/akmods

mkdir -p /etc/pki/akmods/certs
ghcurl "https://github.com/ublue-os/akmods/raw/refs/heads/main/certs/public_key.der" --retry 3 -Lo /etc/pki/akmods/certs/akmods-ublue.der
grep -F -e "Universal Blue" /etc/pki/akmods/certs/akmods-ublue.der

# RPMFUSION Dependent AKMODS
# Write rpmfusion repo files inline instead of installing release RPMs.
# This avoids network-fetching release packages and eliminates 4 extra DNF transactions.
RPMFUSION_FREE_REPO=/etc/yum.repos.d/rpmfusion-free-build.repo
RPMFUSION_NONFREE_REPO=/etc/yum.repos.d/rpmfusion-nonfree-build.repo

cat > "${RPMFUSION_FREE_REPO}" <<'REPOEOF'
[rpmfusion-free]
name=RPM Fusion for Fedora $releasever - Free
baseurl=https://download1.rpmfusion.org/free/fedora/releases/$releasever/Everything/$basearch/os/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1

[rpmfusion-free-updates]
name=RPM Fusion for Fedora $releasever - Free - Updates
baseurl=https://download1.rpmfusion.org/free/fedora/updates/$releasever/$basearch/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1
REPOEOF

cat > "${RPMFUSION_NONFREE_REPO}" <<'REPOEOF'
[rpmfusion-nonfree]
name=RPM Fusion for Fedora $releasever - Nonfree
baseurl=https://download1.rpmfusion.org/nonfree/fedora/releases/$releasever/Everything/$basearch/os/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1

[rpmfusion-nonfree-updates]
name=RPM Fusion for Fedora $releasever - Nonfree - Updates
baseurl=https://download1.rpmfusion.org/nonfree/fedora/updates/$releasever/$basearch/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1
REPOEOF

if [[ "${UBLUE_IMAGE_TAG}" == "beta" ]]; then
    dnf5 -y install \
        v4l2loopback /tmp/akmods/kmods/*v4l2loopback*.rpm || true
else
    dnf5 -y install \
        v4l2loopback /tmp/akmods/kmods/*v4l2loopback*.rpm
fi

# Remove temporary rpmfusion repo files
rm -f "${RPMFUSION_FREE_REPO}" "${RPMFUSION_NONFREE_REPO}"

# Nvidia AKMODS
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    NVIDIA_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods-rpms/manifest.json | cut -d : -f 2)
    tar -xvzf /tmp/akmods-rpms/"$NVIDIA_TARGZ" -C /tmp/
    mv /tmp/rpms/* /tmp/akmods-rpms/

    # Exclude the Golang Nvidia Container Toolkit in Fedora Repo
    # Exclude for non-beta.... doesn't appear to exist for F42 yet?
    if [[ "${UBLUE_IMAGE_TAG}" != "beta" ]]; then
        dnf5 config-manager setopt excludepkgs=golang-github-nvidia-container-toolkit
    else
        # Monkey patch right now...
        if ! grep -q negativo17 <(rpm -qi mesa-dri-drivers); then
            dnf5 -y swap --repo=updates-testing \
                mesa-dri-drivers mesa-dri-drivers
        fi
    fi

    # Install Nvidia RPMs
    # Pre-import ublue-os/staging COPR GPG key: nvidia-install.sh enables this COPR and
    # dnf5 fails with "Signing key not found" on Fedora 44+ if the key isn't already imported.
    rpm --import "https://download.copr.fedorainfracloud.org/results/ublue-os/staging/pubkey.gpg"
    IMAGE_NAME="${BASE_IMAGE_NAME}" AKMODNV_PATH="/tmp/akmods-rpms" MULTILIB=0 /tmp/akmods-rpms/ublue-os/nvidia-install.sh
    rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
    ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so
    tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

    # Install NVIDIA Container Toolkit for CDI-based GPU passthrough in Podman.
    # -base variant only: ships nvidia-ctk + nvidia-cdi-hook, no libnvidia-container,
    # no legacy OCI hook. CDI is the correct path for bootc/rootless containers.
    # Mirrors dakota elements/bluefin-nvidia/nvidia-container-toolkit.bst.
    # NVIDIA's official C toolkit — distinct from Fedora's golang-github-nvidia-container-toolkit.
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
        | tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    dnf5 -y install nvidia-container-toolkit-base
    # Configure for rootless Podman: no cgroup device delegation needed with CDI
    nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place
    # Remove the repo file from the final image
    rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo
fi

# ZFS for stable
if [[ "${AKMODS_FLAVOR}" =~ coreos ]]; then
    ZFS_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods-zfs/manifest.json | cut -d : -f 2)
    tar -xvzf /tmp/akmods-zfs/"$ZFS_TARGZ" -C /tmp/
    mv /tmp/rpms/* /tmp/akmods-zfs/

    # Declare ZFS RPMs
    ZFS_RPMS=(
        /tmp/akmods-zfs/kmods/zfs/kmod-zfs-"${KERNEL}"-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libnvpair[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libuutil[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libzfs[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/libzpool[0-9]-*.rpm
        /tmp/akmods-zfs/kmods/zfs/python3-pyzfs-*.rpm
        /tmp/akmods-zfs/kmods/zfs/zfs-*.rpm
        pv
    )

    # Install
    dnf5 -y install "${ZFS_RPMS[@]}"

    # Depmod and autoload
    depmod -a -v "${KERNEL}"
    echo "zfs" >/usr/lib/modules-load.d/zfs.conf
fi

dnf5 copr disable -y ublue-os/akmods

# Generate initramfs here in Stage 1 so Stage 2 can skip it on system_files-only
# rebuilds (when Stage 1 is a Docker cache hit). The marker file signals to
# 19-initramfs.sh that dracut already ran for this kernel.
echo "Generating initramfs for ${KERNEL}"
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${KERNEL}" --reproducible --tmpdir /boot \
    -v --add "ostree dmsquash-live dmsquash-live-autooverlay" \
    -f "/lib/modules/${KERNEL}/initramfs.img"
chmod 0600 "/lib/modules/${KERNEL}/initramfs.img"
touch "/lib/modules/${KERNEL}/.bluefin-initramfs-done"

echo "::endgroup::"
