#!/usr/bin/env bats
# Drift gate for the GNOME extension roster.
#
# The roster is stated twice and joined by nothing:
#   1. .gitmodules              -- which extension trees are vendored
#   2. build-gnome-extensions.sh -- what is done to each of them
#
# Both restatements fail open. A submodule added under .../extensions/tmp/ is
# staging-only: build-gnome-extensions.sh ends with
# `rm -rf /usr/share/gnome-shell/extensions/tmp`, so a staging tree the script
# never `mv`s out is deleted and the extension silently vanishes from the image
# with a green build. A submodule added outside tmp/ that the script never
# compiles schemas for ships with uncompiled gschemas and loads as a runtime
# error, again with a green build.
#
# These tests tie the two lists together so either drift fails loudly at PR
# time instead of at boot.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ROSTER_PY='
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
EXT_PREFIX = "system_files/shared/usr/share/gnome-shell/extensions/"
STAGING_PREFIX = EXT_PREFIX + "tmp/"
IMAGE_EXT_DIR = "/usr/share/gnome-shell/extensions"

script_path = root / "build_files" / "shared" / "build-gnome-extensions.sh"
script = script_path.read_text(encoding="utf-8")

paths = re.findall(
    r"^\s*path\s*=\s*(\S+)\s*$",
    (root / ".gitmodules").read_text(encoding="utf-8"),
    re.MULTILINE,
)
extension_paths = [p for p in paths if p.startswith(EXT_PREFIX)]

# First path segment under tmp/ is the staging tree the script must rescue.
staging = sorted({p[len(STAGING_PREFIX):].split("/")[0] for p in extension_paths if p.startswith(STAGING_PREFIX)})
installed = sorted({p[len(EXT_PREFIX):] for p in extension_paths if not p.startswith(STAGING_PREFIX)})

moved_out = set(re.findall(rf"\bmv\s+{re.escape(IMAGE_EXT_DIR)}/tmp/([^/\s]+)", script))
move_targets = set(re.findall(rf"\bmv\s+\S+\s+{re.escape(IMAGE_EXT_DIR)}/([^/\s]+)", script))
referenced = set(re.findall(rf"{re.escape(IMAGE_EXT_DIR)}/([^/\s]+)", script)) - {"tmp"}
'

@test "the roster premise holds: extensions are vendored and tmp/ is purged" {
    run python3 -c "${ROSTER_PY}"'
if not extension_paths:
    print(".gitmodules declares no gnome-shell extension submodules -- gate is vacuous", file=sys.stderr)
    raise SystemExit(1)
if f"rm -rf {IMAGE_EXT_DIR}/tmp" not in script:
    print(
        f"{script_path.name} no longer purges {IMAGE_EXT_DIR}/tmp; the staging "
        "contract this gate enforces has changed and these tests need updating",
        file=sys.stderr,
    )
    raise SystemExit(1)
' "${REPO_ROOT}"

    [ "$status" -eq 0 ]
}

@test "every staged extension submodule is moved out before tmp/ is purged" {
    run python3 -c "${ROSTER_PY}"'
orphans = [name for name in staging if name not in moved_out]
if orphans:
    print(
        "staging submodules deleted by the tmp/ purge because "
        f"{script_path.name} never moves them out: " + ", ".join(orphans),
        file=sys.stderr,
    )
    raise SystemExit(1)
' "${REPO_ROOT}"

    [ "$status" -eq 0 ]
}

@test "every vendored extension submodule is handled by build-gnome-extensions.sh" {
    run python3 -c "${ROSTER_PY}"'
orphans = [name for name in installed if name not in referenced]
if orphans:
    print(
        f"extension submodules never handled by {script_path.name} (they ship "
        "with uncompiled schemas): " + ", ".join(orphans),
        file=sys.stderr,
    )
    raise SystemExit(1)
' "${REPO_ROOT}"

    [ "$status" -eq 0 ]
}

@test "build-gnome-extensions.sh references no undeclared extension" {
    run python3 -c "${ROSTER_PY}"'
known = set(installed) | move_targets
unknown = sorted(referenced - known)
if unknown:
    print(
        f"{script_path.name} builds extensions that .gitmodules does not "
        "vendor: " + ", ".join(unknown),
        file=sys.stderr,
    )
    raise SystemExit(1)
' "${REPO_ROOT}"

    [ "$status" -eq 0 ]
}
