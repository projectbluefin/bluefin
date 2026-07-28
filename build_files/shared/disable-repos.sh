#!/usr/bin/bash
# Disable all third-party repos that were enabled during the build.
# Source this file and call disable_third_party_repos.
# Called by: build_files/base/17-cleanup.sh

disable_third_party_repos() {
    local REPOS_DIR="${REPOS_DIR:-/etc/yum.repos.d}"

    # Specific named repos enabled by build scripts
    for repo in fedora-multimedia tailscale fedora-cisco-openh264; do
        if [[ -f "${REPOS_DIR}/${repo}.repo" ]]; then
            sed -i 's@enabled=1@enabled=0@g' "${REPOS_DIR}/${repo}.repo"
        fi
    done

    # All COPR repos (isolated helpers disable them, but ensure here)
    for repo in "${REPOS_DIR}"/_copr:*.repo; do
        [[ -f "$repo" ]] && sed -i 's@enabled=1@enabled=0@g' "$repo"
    done

    # RPM Fusion repos
    for repo in "${REPOS_DIR}"/rpmfusion-*.repo; do
        [[ -f "$repo" ]] && sed -i 's@enabled=1@enabled=0@g' "$repo"
    done

    # CoreOS pool if present
    if [[ -f "${REPOS_DIR}/fedora-coreos-pool.repo" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "${REPOS_DIR}/fedora-coreos-pool.repo"
    fi
}
