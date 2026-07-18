ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG BASE_IMAGE="quay.io/fedora-ostree-desktops/silverblue"
# BASE_IMAGE_REF is resolved to BASE_IMAGE:FEDORA_MAJOR_VERSION@digest after cosign verify.
# Defaults to tag-only for local builds where digest is not resolved.
ARG BASE_IMAGE_REF="${BASE_IMAGE}:${FEDORA_MAJOR_VERSION}"
ARG COMMON_IMAGE="ghcr.io/projectbluefin/common:latest"
ARG COMMON_IMAGE_SHA=""
ARG BREW_IMAGE="ghcr.io/ublue-os/brew:latest"
ARG BREW_IMAGE_SHA=""

FROM ${COMMON_IMAGE}@${COMMON_IMAGE_SHA} AS common
FROM ${BREW_IMAGE}@${BREW_IMAGE_SHA} AS brew

FROM scratch AS ctx
COPY /system_files /system_files
COPY /build_files /build_files
COPY /image-versions.yml /image-versions.yml
COPY --from=common /system_files/shared /system_files/shared
COPY --from=common /system_files/bluefin /system_files/shared
COPY --from=brew /system_files /system_files/shared

## bluefin image section
# hadolint ignore=DL3006
FROM ${BASE_IMAGE_REF} AS base-common

ARG AKMODS_FLAVOR="coreos-stable"
ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG IMAGE_NAME="bluefin"
ARG IMAGE_VENDOR="projectbluefin"
ARG KERNEL="6.10.10-200.fc40.x86_64"
ARG UBLUE_IMAGE_TAG="stable"
ARG IMAGE_FLAVOR=""

# Stage 1 — Package installs only (cache key: build_files/)
# Runs the package-install layer (`03-packages.sh`, `04-install-kernel-akmods.sh`,
# `05-override-install.sh`) before any system_files overlay work.
# Narrow mount (build_files/ only) enables granular layer caching:
# a system_files-only PR change gets a cache hit here, saving 20-80 min.
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/build_files,target=/ctx/build_files \
    --mount=type=bind,from=ctx,source=/image-versions.yml,target=/ctx/image-versions.yml \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    bash -euo pipefail -c ' \
        dnf5 config-manager setopt keepcache=1 && \
        dnf5 config-manager setopt install_weak_deps=0 && \
        dnf5 -y swap fedora-logos generic-logos && \
        rpm --erase --nodeps --nodb generic-logos && \
        mkdir -p /tmp/scripts/helpers && \
        install -Dm0755 /ctx/build_files/shared/utils/ghcurl /tmp/scripts/helpers/ghcurl && \
        export PATH="/tmp/scripts/helpers:$PATH" && \
        /ctx/build_files/base/03-packages.sh && \
        /ctx/build_files/base/04-install-kernel-akmods.sh && \
        /ctx/build_files/base/05-override-install.sh \
    '

# hadolint ignore=DL3006
FROM base-common AS extension-builder

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    bash -euo pipefail -c ' \
        dnf5 -y install glib2-devel meson sassc cmake dbus-devel \
    '

RUN --mount=type=bind,from=ctx,source=/system_files/shared/usr/share/gnome-shell/extensions,target=/ctx/extensions \
    --mount=type=bind,from=ctx,source=/build_files/shared/build-gnome-extensions.sh,target=/ctx/build_files/shared/build-gnome-extensions.sh \
    bash -euo pipefail -c ' \
        mkdir -p /usr/share/gnome-shell/extensions && \
        rsync -rvK /ctx/extensions/ /usr/share/gnome-shell/extensions/ && \
        bash /ctx/build_files/shared/build-gnome-extensions.sh \
    '

# Per-build metadata: declared here so they don't bust Stage 1's cache key.
ARG SHA_HEAD_SHORT="dedbeef"
ARG VERSION=""

FROM base-common AS base

ARG AKMODS_FLAVOR="coreos-stable"
ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG IMAGE_NAME="bluefin"
ARG IMAGE_VENDOR="projectbluefin"
ARG KERNEL="6.10.10-200.fc40.x86_64"
ARG UBLUE_IMAGE_TAG="stable"
ARG IMAGE_FLAVOR=""
ARG SHA_HEAD_SHORT="dedbeef"
ARG VERSION=""

COPY --from=extension-builder /usr/share/gnome-shell/extensions /usr/share/gnome-shell/extensions
COPY --from=extension-builder /usr/share/glib-2.0/schemas /usr/share/glib-2.0/schemas

# Stage 2: overlay system_files, finalize extensions, clean up, and finalize the image.
# Narrow mount (system_files/ + build_files/shared) means package-script changes
# do NOT invalidate this stage when build_files/base is unchanged.
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=ctx,source=/system_files,target=/ctx/system_files \
    --mount=type=bind,from=ctx,source=/build_files/shared,target=/ctx/build_files/shared \
    --mount=type=bind,from=ctx,source=/build_files/base/00-image-info.sh,target=/ctx/build_files/base/00-image-info.sh \
    --mount=type=bind,from=ctx,source=/build_files/base/17-cleanup.sh,target=/ctx/build_files/base/17-cleanup.sh \
    --mount=type=bind,from=ctx,source=/build_files/base/19-initramfs.sh,target=/ctx/build_files/base/19-initramfs.sh \
    --mount=type=bind,from=ctx,source=/build_files/base/20-tests.sh,target=/ctx/build_files/base/20-tests.sh \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    bash -euo pipefail -c ' \
        rsync -rvK --exclude="/usr/share/gnome-shell/extensions/***" /ctx/system_files/shared/ / && \
        mkdir -p /tmp/scripts/helpers && \
        install -Dm0755 /ctx/build_files/shared/utils/ghcurl /tmp/scripts/helpers/ghcurl && \
        export PATH="/tmp/scripts/helpers:$PATH" && \
        /ctx/build_files/base/00-image-info.sh && \
        bash /ctx/build_files/shared/finalize-gnome-extensions.sh && \
        /ctx/build_files/base/17-cleanup.sh && \
        /ctx/build_files/base/19-initramfs.sh && \
        /ctx/build_files/shared/validate-repos.sh && \
        /ctx/build_files/shared/clean-stage.sh && \
        /ctx/build_files/base/20-tests.sh \
    '

# Embed the Stable container-native ISO contract after Stage 2. This runs
# without the /boot tmpfs so Titanoboa can consume the committed EFI payload.
RUN --mount=type=bind,from=ctx,source=/build_files/base/21-container-native-iso.sh,target=/ctx/build_files/base/21-container-native-iso.sh \
    --mount=type=bind,from=ctx,source=/build_files/shared/utils/ghcurl,target=/ctx/build_files/shared/utils/ghcurl \
    --mount=type=secret,id=GITHUB_TOKEN \
    bash -euo pipefail -c ' \
        mkdir -p /var/cache/bluefin-iso/helpers && \
        install -Dm0755 /ctx/build_files/shared/utils/ghcurl /var/cache/bluefin-iso/helpers/ghcurl && \
        export PATH="/var/cache/bluefin-iso/helpers:$PATH" && \
        /ctx/build_files/base/21-container-native-iso.sh && \
        rm -rf /var/cache/bluefin-iso \
    '

# Makes `/opt` writeable by default
# Needs to be here to make the main image build strict (no /opt there)
# This is for downstream images/stuff like k0s
RUN rm -rf /opt && ln -s /var/opt /opt

CMD ["/sbin/init"]

RUN bootc container lint --fatal-warnings --skip nonempty-boot
