#!/usr/bin/bash
# Shared package management helpers for build scripts.
# Source this file to use the helpers.
# Note: COPR-specific helpers stay in copr-helpers.sh (security boundary).

# Install packages from Fedora (or other already-enabled) repos.
# Usage: install_fedora_packages PACKAGES_ARRAY_NAME
install_fedora_packages() {
    local -n _packages=$1
    if [[ ${#_packages[@]} -eq 0 ]]; then
        echo "install_fedora_packages: no packages to install"
        return 0
    fi
    echo "Installing ${#_packages[@]} packages from Fedora repos..."
    dnf5 -y install "${_packages[@]}"
}

# Remove packages that conflict with or are replaced by image content.
# Silently skips any packages that are not installed.
# Usage: remove_excluded_packages PACKAGES_ARRAY_NAME
remove_excluded_packages() {
    local -n _packages=$1
    if [[ ${#_packages[@]} -eq 0 ]]; then
        return 0
    fi
    readarray -t _installed < <(rpm -qa --queryformat='%{NAME}\n' "${_packages[@]}" 2>/dev/null || true)
    if [[ ${#_installed[@]} -gt 0 ]]; then
        echo "Removing ${#_installed[@]} excluded packages: ${_installed[*]}"
        dnf5 -y remove "${_installed[@]}"
    else
        echo "No excluded packages found to remove."
    fi
}

# Assert that every package in the list is installed; exit 1 if any are missing.
# Usage: assert_packages_present PACKAGES_ARRAY_NAME
assert_packages_present() {
    local -n _packages=$1
    local -a missing=()
    for pkg in "${_packages[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Required packages not installed: ${missing[*]}"
        exit 1
    fi
    echo "✅ All ${#_packages[@]} required packages are present."
}
