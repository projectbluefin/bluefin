#!/usr/bin/bash
set -euo pipefail

# SECURITY INVARIANT — DO NOT SIMPLIFY THIS FUNCTION
#
# The enable→disable→install sequence is a deliberate security boundary:
#   1. copr enable    — makes the COPR repo available
#   2. copr disable   — IMMEDIATELY disables it (NOT a cleanup step)
#   3. dnf5 install --enablerepo=  — installs only from the named repo
#
# Step 2 is NOT cleanup. Disabling the COPR before installing prevents
# an enabled COPR from injecting fake versions of Fedora base packages into
# subsequent dnf5 install calls (repo priority poisoning attack).
#
# Simplifying this to "copr enable && dnf5 install" breaks the security model.
# See docs/skills/security/references/copr-isolation.md for details.
copr_install_isolated() {
    local copr_name="$1"
    shift
    local packages=("$@")

    if [[ ${#packages[@]} -eq 0 ]]; then
        echo "ERROR: No packages specified for copr_install_isolated"
        return 1
    fi

    repo_id="copr:copr.fedorainfracloud.org:${copr_name//\//:}"

    echo "Installing ${packages[*]} from COPR $copr_name (isolated)"

    dnf5 -y copr enable "$copr_name"
    dnf5 -y copr disable "$copr_name"
    dnf5 -y install --enablerepo="$repo_id" "${packages[@]}"

    echo "Installed ${packages[*]} from $copr_name"
}
