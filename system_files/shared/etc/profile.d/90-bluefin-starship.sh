# shellcheck shell=sh
# Initialize starship as the default shell prompt.
# starship is installed by brew-preinstall at first login; it is no longer
# baked into the image. Check both the system PATH (covers any future case
# where it is on the image) and the known brew bin location so the prompt
# works from the very first login session, before brew shellenv is sourced.
#
# Falls back transparently to the default bash prompt if starship is absent
# (e.g. brew-preinstall hasn't run yet, or the user removed it).

if command -v starship >/dev/null 2>&1; then
    _starship_bin="starship"
elif [ -x "/var/home/linuxbrew/.linuxbrew/bin/starship" ]; then
    _starship_bin="/var/home/linuxbrew/.linuxbrew/bin/starship"
else
    return 0
fi

if [ "$(basename "$(readlink /proc/$$/exe)")" = "bash" ]; then
    eval "$("$_starship_bin" init bash)"
fi

unset _starship_bin
