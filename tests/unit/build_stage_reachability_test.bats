#!/usr/bin/env bats
# Reachability gate for the ordered build-stage sequence.
#
# The Containerfile enumerates the `build_files/base/NN-*.sh` stages by hand
# inside its RUN blocks. Nothing else ties the directory listing to that
# enumeration, so a stage can be added -- or silently unwired -- and still look
# alive because some retired orchestrator references it. These tests make that
# state fail loudly instead.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

@test "every build_files/base script is invoked by the Containerfile" {
    run python3 -c '
from pathlib import Path
import sys

root = Path(sys.argv[1])
containerfile = (root / "Containerfile").read_text()
scripts = sorted(p.name for p in (root / "build_files" / "base").glob("*.sh"))
orphans = [name for name in scripts if f"/build_files/base/{name}" not in containerfile]
if orphans:
    print(
        "build_files/base scripts not invoked by Containerfile: "
        + ", ".join(orphans),
        file=sys.stderr,
    )
    raise SystemExit(1)
if not scripts:
    print("no build_files/base scripts found -- test is not exercising anything", file=sys.stderr)
    raise SystemExit(1)
' "${REPO_ROOT}"

    [ "$status" -eq 0 ]
}

@test "no build_files script is orphaned behind a non-Containerfile orchestrator" {
    run python3 -c '
from pathlib import Path
import sys

root = Path(sys.argv[1])
build_files = root / "build_files"
containerfile = (root / "Containerfile").read_text()

# Shell entrypoints under build_files/ must be reachable from the Containerfile,
# either directly or by being sourced from a script that is. A standalone
# orchestrator that re-runs the stage list is a second source of truth and is
# exactly what let 18-workarounds.sh drift out of the image (see issue #1147).
scripts = sorted(build_files.rglob("*.sh"))
sources = {p: p.read_text() for p in scripts}

def reachable(path):
    rel = path.relative_to(root).as_posix()
    if f"/{rel}" in containerfile:
        return True
    # Match on the build_files-relative path, not the bare basename: a bare
    # name like "build.sh" collides with unrelated vendored scripts (see
    # build-gnome-extensions.sh) and would mark a genuine orphan as reachable.
    # Every in-repo cross-reference uses a full /ctx/build_files/... path.
    needle = path.relative_to(build_files).as_posix()
    return any(
        needle in text
        for other, text in sources.items()
        if other != path and f"/{other.relative_to(root).as_posix()}" in containerfile
    )

orphans = [p.relative_to(root).as_posix() for p in scripts if not reachable(p)]
if orphans:
    print("unreachable build_files scripts: " + ", ".join(orphans), file=sys.stderr)
    raise SystemExit(1)
' "${REPO_ROOT}"

    [ "$status" -eq 0 ]
}

@test "the orphan kernel-module sweep has exactly one implementation" {
    run python3 -c '
from pathlib import Path
import sys

root = Path(sys.argv[1])
marker = "no matching kernel-core RPM"
owners = sorted(
    p.relative_to(root).as_posix()
    for p in (root / "build_files").rglob("*.sh")
    if marker in p.read_text()
)
if owners != ["build_files/base/17-cleanup.sh"]:
    print(
        "orphan kernel-module sweep must live only in 17-cleanup.sh, found: "
        + ", ".join(owners),
        file=sys.stderr,
    )
    raise SystemExit(1)
' "${REPO_ROOT}"

    [ "$status" -eq 0 ]
}
