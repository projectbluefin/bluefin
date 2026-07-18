#!/usr/bin/env bats
# Unit tests for build_files/base/04-install-kernel-akmods.sh.
# Run with: bats tests/unit/04-install-kernel-akmods_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT="${SCRIPT_DIR}/../../build_files/base/04-install-kernel-akmods.sh"

KERNEL_VER="6.12.0-200.fc42.x86_64"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/04-kernel.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    DNF_LOG="${TEST_ROOT}/dnf.log"
    SKOPEO_LOG="${TEST_ROOT}/skopeo.log"
    DRACUT_LOG="${TEST_ROOT}/dracut.log"

    mkdir -p "${STUB_BIN}"
    mkdir -p "${TEST_ROOT}/tmp/kernel-rpms"
    mkdir -p "${TEST_ROOT}/tmp/rpms"
    mkdir -p "${TEST_ROOT}/etc/yum.repos.d"
    mkdir -p "${TEST_ROOT}/etc/pki/akmods/certs"
    mkdir -p "${TEST_ROOT}/lib/modules/${KERNEL_VER}"
    mkdir -p "${TEST_ROOT}/usr/lib/bootc/kargs.d"
    mkdir -p "${TEST_ROOT}/usr/lib/modules-load.d"
    mkdir -p "${TEST_ROOT}/usr/share/vulkan/icd.d"
    mkdir -p "${TEST_ROOT}/usr/lib64"

    # Fake kernel RPMs (kernel-rpms dir is pre-populated in the container build;
    # in tests we just need the globs to expand to something)
    touch "${TEST_ROOT}/tmp/kernel-rpms/kernel-6.12.0-200.fc42.x86_64.rpm"
    touch "${TEST_ROOT}/tmp/kernel-rpms/kernel-core-6.12.0.fc42.x86_64.rpm"
    touch "${TEST_ROOT}/tmp/kernel-rpms/kernel-modules-6.12.0.fc42.x86_64.rpm"
    touch "${TEST_ROOT}/tmp/kernel-rpms/kernel-devel-6.12.0.fc42.x86_64.rpm"

    export PATH="${STUB_BIN}:${PATH}"
    export DNF_LOG SKOPEO_LOG DRACUT_LOG TEST_ROOT

    # ── rpm stub ─────────────────────────────────────────────────────────────
    # Handles:  rpm -E %fedora  →  "44"
    #           rpm --erase ...  →  exit 0
    #           rpm --import ... →  exit 0
    #           rpm -qi ...     →  exit 0 (empty output)
    cat > "${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
for arg in "$@"; do
    if [[ "${arg}" == "%fedora" ]]; then echo "44"; exit 0; fi
done
exit 0
EOF
    chmod +x "${STUB_BIN}/rpm"

    # ── dnf5 stub ────────────────────────────────────────────────────────────
    cat > "${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
echo "dnf5 $*" >> "${DNF_LOG}"
exit 0
EOF
    chmod +x "${STUB_BIN}/dnf5"

    # ── skopeo stub ──────────────────────────────────────────────────────────
    # Creates pull dir with a fake manifest.json and a fake tarball file.
    cat > "${STUB_BIN}/skopeo" <<'STUBEOF'
#!/usr/bin/bash
echo "skopeo $*" >> "${SKOPEO_LOG}"
for arg in "$@"; do
    if [[ "${arg}" == dir:* ]]; then
        target="${arg#dir:}"
        mkdir -p "${target}"
        printf '{"layers":[{"digest":"sha256:abc123fake"}]}\n' > "${target}/manifest.json"
        touch "${target}/abc123fake"
    fi
done
exit 0
STUBEOF
    chmod +x "${STUB_BIN}/skopeo"

    # ── jq stub ──────────────────────────────────────────────────────────────
    # Returns a constant digest string; cut -d : -f 2 gives "abc123fake"
    cat > "${STUB_BIN}/jq" <<'EOF'
#!/usr/bin/bash
echo "sha256:abc123fake"
exit 0
EOF
    chmod +x "${STUB_BIN}/jq"

    # ── tar stub ─────────────────────────────────────────────────────────────
    # Extracts nothing but creates the directory structure the script expects
    # inside the -C target:  rpms/kmods/, rpms/ublue-os/, rpms/kmods/zfs/
    cat > "${STUB_BIN}/tar" <<'STUBEOF'
#!/usr/bin/bash
target=""
prev=""
for i in "$@"; do
    if [[ "${prev}" == "-C" ]]; then target="${i}"; fi
    prev="${i}"
done
if [[ -n "${target}" ]]; then
    mkdir -p "${target}/rpms/kmods"
    touch "${target}/rpms/kmods/kmod-v4l2loopback-0.1.rpm"
    mkdir -p "${target}/rpms/ublue-os"
    printf '#!/usr/bin/bash\nexit 0\n' > "${target}/rpms/ublue-os/nvidia-install.sh"
    chmod +x "${target}/rpms/ublue-os/nvidia-install.sh"
    mkdir -p "${target}/rpms/kmods/zfs"
    touch "${target}/rpms/kmods/zfs/kmod-zfs-${KERNEL}-1.rpm"
fi
exit 0
STUBEOF
    chmod +x "${STUB_BIN}/tar"

    # ── ghcurl stub ──────────────────────────────────────────────────────────
    # Writes "Universal Blue certificate" to the -Lo <path> destination so
    # the downstream grep check passes.
    cat > "${STUB_BIN}/ghcurl" <<'EOF'
#!/usr/bin/bash
lo_next=0
for arg in "$@"; do
    if [[ "${lo_next}" == "1" ]]; then
        mkdir -p "$(dirname "${arg}")"
        printf 'Universal Blue certificate\n' > "${arg}"
        lo_next=0
    fi
    if [[ "${arg}" == "-Lo" ]]; then lo_next=1; fi
done
exit 0
EOF
    chmod +x "${STUB_BIN}/ghcurl"

    # ── dracut stub ──────────────────────────────────────────────────────────
    # Records call args and creates the initramfs file (-f <path>).
    cat > "${STUB_BIN}/dracut" <<'STUBEOF'
#!/usr/bin/bash
echo "dracut $*" >> "${DRACUT_LOG}"
prev=""
for arg in "$@"; do
    if [[ "${prev}" == "-f" ]]; then
        mkdir -p "$(dirname "${arg}")"
        touch "${arg}"
    fi
    prev="${arg}"
done
exit 0
STUBEOF
    chmod +x "${STUB_BIN}/dracut"

    # ── depmod stub ──────────────────────────────────────────────────────────
    cat > "${STUB_BIN}/depmod" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/depmod"

    # ── curl stub ────────────────────────────────────────────────────────────
    # Used by the nvidia CDI block: curl ... | tee <repo-file>
    # Just emit a line to stdout so tee has something to write.
    cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/bash
echo "[nvidia-container-toolkit]"
exit 0
EOF
    chmod +x "${STUB_BIN}/curl"

    # ── nvidia-ctk stub ──────────────────────────────────────────────────────
    # Used by nvidia CDI block to configure container runtime.
    cat > "${STUB_BIN}/nvidia-ctk" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/nvidia-ctk"

    # ── ln stub ──────────────────────────────────────────────────────────────
    cat > "${STUB_BIN}/ln" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "${STUB_BIN}/ln"

    # ── Patch the script ─────────────────────────────────────────────────────
    # Redirect absolute system paths into the sandbox; replace /usr/bin/dracut
    # with the PATH-based stub.
    PATCHED_SCRIPT="${TEST_ROOT}/04-patched.sh"
    sed \
        -e "s|/tmp/|${TEST_ROOT}/tmp/|g" \
        -e "s|/etc/yum.repos.d/|${TEST_ROOT}/etc/yum.repos.d/|g" \
        -e "s|/etc/pki/akmods/|${TEST_ROOT}/etc/pki/akmods/|g" \
        -e "s|/lib/modules/|${TEST_ROOT}/lib/modules/|g" \
        -e "s|/usr/bin/dracut|dracut|g" \
        -e "s|/usr/lib/bootc/kargs.d/|${TEST_ROOT}/usr/lib/bootc/kargs.d/|g" \
        -e "s|/usr/lib/modules-load.d/|${TEST_ROOT}/usr/lib/modules-load.d/|g" \
        -e "s|/usr/share/vulkan/icd.d/|${TEST_ROOT}/usr/share/vulkan/icd.d/|g" \
        -e "s|/usr/lib64/libnvidia-ml\.so|${TEST_ROOT}/usr/lib64/libnvidia-ml.so|g" \
        "${SCRIPT}" > "${PATCHED_SCRIPT}"
    chmod +x "${PATCHED_SCRIPT}"

    # ── Default env ──────────────────────────────────────────────────────────
    export KERNEL="${KERNEL_VER}"
    export IMAGE_NAME="bluefin"
    export AKMODS_FLAVOR="main"
    export UBLUE_IMAGE_TAG="stable"
    export BASE_IMAGE_NAME="bluefin"
    export PATCHED_SCRIPT
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Happy path — non-nvidia, non-coreos, stable
# ─────────────────────────────────────────────────────────────────────────────

@test "04-kernel-akmods: exits 0 for non-nvidia, non-coreos, stable build" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
}

@test "04-kernel-akmods: initramfs marker file written after successful run" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/lib/modules/${KERNEL_VER}/.bluefin-initramfs-done" ]
}

@test "04-kernel-akmods: cached initramfs includes ISO live modules" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${DRACUT_LOG}" ]
    grep -q -- "--reproducible" "${DRACUT_LOG}"
    grep -q -- "--add ostree dmsquash-live dmsquash-live-autooverlay" "${DRACUT_LOG}"
}

# ─────────────────────────────────────────────────────────────────────────────
# RPMFusion repo file lifecycle
# ─────────────────────────────────────────────────────────────────────────────

@test "04-kernel-akmods: rpmfusion-free repo created then removed" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # repo file must NOT persist after the script finishes (rm -f cleans it up)
    [ ! -f "${TEST_ROOT}/etc/yum.repos.d/rpmfusion-free-build.repo" ]
}

@test "04-kernel-akmods: rpmfusion-nonfree repo created then removed" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -f "${TEST_ROOT}/etc/yum.repos.d/rpmfusion-nonfree-build.repo" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Beta flag
# ─────────────────────────────────────────────────────────────────────────────

@test "04-kernel-akmods: beta flag enables updates-testing repo" {
    export UBLUE_IMAGE_TAG="beta"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${DNF_LOG}" ]
    grep -q "updates-testing.enabled=1" "${DNF_LOG}"
}

@test "04-kernel-akmods: stable build does NOT enable updates-testing repo" {
    export UBLUE_IMAGE_TAG="stable"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # Log may not exist at all; if it does, must not contain updates-testing.enabled=1
    if [ -f "${DNF_LOG}" ]; then
        ! grep -q "updates-testing.enabled=1" "${DNF_LOG}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Parallel pull conditionals
# ─────────────────────────────────────────────────────────────────────────────

@test "04-kernel-akmods: akmods pull always fires" {
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${SKOPEO_LOG}" ]
    grep -q "akmods:" "${SKOPEO_LOG}"
}

@test "04-kernel-akmods: nvidia pull fires only when IMAGE_NAME contains nvidia" {
    export IMAGE_NAME="bluefin"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    # no nvidia pull for a non-nvidia image
    if [ -f "${SKOPEO_LOG}" ]; then
        ! grep -q "akmods-nvidia-open" "${SKOPEO_LOG}"
    fi
}

@test "04-kernel-akmods: nvidia pull fires when IMAGE_NAME contains nvidia" {
    export IMAGE_NAME="bluefin-nvidia"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${SKOPEO_LOG}" ]
    grep -q "akmods-nvidia-open" "${SKOPEO_LOG}"
}

@test "04-kernel-akmods: zfs pull fires only when AKMODS_FLAVOR contains coreos" {
    export AKMODS_FLAVOR="main"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    if [ -f "${SKOPEO_LOG}" ]; then
        ! grep -q "akmods-zfs" "${SKOPEO_LOG}"
    fi
}

@test "04-kernel-akmods: zfs pull fires when AKMODS_FLAVOR contains coreos" {
    export AKMODS_FLAVOR="coreos-stable"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${SKOPEO_LOG}" ]
    grep -q "akmods-zfs" "${SKOPEO_LOG}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Pull failure handling
# ─────────────────────────────────────────────────────────────────────────────

@test "04-kernel-akmods: failing akmods pull propagates as non-zero exit" {
    # Override skopeo to always fail
    cat > "${STUB_BIN}/skopeo" <<'FAILEOF'
#!/usr/bin/bash
echo "skopeo $*" >> "${SKOPEO_LOG}"
exit 1
FAILEOF
    chmod +x "${STUB_BIN}/skopeo"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# ZFS autoload config (coreos flavor)
# ─────────────────────────────────────────────────────────────────────────────

@test "04-kernel-akmods: zfs autoload config written for coreos flavor" {
    export AKMODS_FLAVOR="coreos-stable"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/lib/modules-load.d/zfs.conf" ]
    grep -q "zfs" "${TEST_ROOT}/usr/lib/modules-load.d/zfs.conf"
}

@test "04-kernel-akmods: zfs autoload config NOT written for non-coreos flavor" {
    export AKMODS_FLAVOR="main"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -f "${TEST_ROOT}/usr/lib/modules-load.d/zfs.conf" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Nvidia kargs.d (nvidia image)
# ─────────────────────────────────────────────────────────────────────────────

@test "04-kernel-akmods: nvidia kargs.d written for nvidia image" {
    export IMAGE_NAME="bluefin-nvidia"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_ROOT}/usr/lib/bootc/kargs.d/00-nvidia.toml" ]
    grep -q "rd.driver.blacklist=nouveau" \
        "${TEST_ROOT}/usr/lib/bootc/kargs.d/00-nvidia.toml"
}

@test "04-kernel-akmods: nvidia kargs.d NOT written for non-nvidia image" {
    export IMAGE_NAME="bluefin"
    run bash "${PATCHED_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -f "${TEST_ROOT}/usr/lib/bootc/kargs.d/00-nvidia.toml" ]
}
