#!/usr/bin/bash

set -eoux pipefail

echo "::group:: ===$(basename "$0")==="

rm -f /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

# Tag all compiled GNOME extensions for the rechunker so they get their
# own layer and don't share with unrelated content (user.component = component name)
setfattr -n user.component -v gnome-extensions /usr/share/gnome-shell/extensions/

echo "::endgroup::"
