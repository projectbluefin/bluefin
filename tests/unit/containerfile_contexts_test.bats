#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
CONTAINERFILE="${SCRIPT_DIR}/../../Containerfile"

@test "Stage 1 context (ctx-build) contains only build_files and image-versions.yml" {
    run python3 -c '
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
start = lines.index("FROM scratch AS ctx-build")
end = next(index for index in range(start + 1, len(lines)) if lines[index].startswith("FROM "))
copies = {
    line.split()[1]
    for line in lines[start + 1:end]
    if line.startswith("COPY ") and not line.startswith("COPY --from")
}
expected = {
    "/build_files",
    "/image-versions.yml",
}
if copies != expected:
    print(f"unexpected ctx-build inputs: {sorted(copies ^ expected)}", file=sys.stderr)
    raise SystemExit(1)

# The whole build_files dir and image-versions.yml are Stage 1-only mounts.
# Lock them to ctx-build so an accidental rewiring to the wide ctx fails
# loudly instead of silently coupling Stage 1 to every system_files edit.
stage1_mounts = [
    line for line in lines
    if "source=/build_files,target=" in line or "source=/image-versions.yml" in line
]
if len(stage1_mounts) != 2 or any("from=ctx-build" not in line for line in stage1_mounts):
    print("build_files and image-versions.yml must mount from ctx-build only", file=sys.stderr)
    raise SystemExit(1)
' "${CONTAINERFILE}"

    [ "$status" -eq 0 ]
}

@test "Stage 2 context contains only its build_files inputs" {
    run python3 -c '
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
start = lines.index("FROM scratch AS ctx")
end = next(index for index in range(start + 1, len(lines)) if lines[index].startswith("FROM "))
copies = {
    line.split()[1]
    for line in lines[start + 1:end]
    if line.startswith("COPY /build_files/")
}
expected = {
    "/build_files/base/00-image-info.sh",
    "/build_files/base/17-cleanup.sh",
    "/build_files/base/19-initramfs.sh",
    "/build_files/base/20-tests.sh",
    "/build_files/shared/build-gnome-extensions.sh",
    "/build_files/shared/checkpoint-rpmdb.sh",
    "/build_files/shared/clean-stage.sh",
    "/build_files/shared/disable-repos.sh",
    "/build_files/shared/finalize-gnome-extensions.sh",
    "/build_files/shared/utils/ghcurl",
    "/build_files/shared/validate-repos.sh",
}
if copies != expected:
    print(f"unexpected ctx build inputs: {sorted(copies ^ expected)}", file=sys.stderr)
    raise SystemExit(1)
' "${CONTAINERFILE}"

    [ "$status" -eq 0 ]
}

@test "ISO context contains only the ISO script and ghcurl" {
    run python3 -c '
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
start = lines.index("FROM scratch AS ctx-iso")
end = next(index for index in range(start + 1, len(lines)) if lines[index].startswith("FROM "))
copies = {
    line.split()[1]
    for line in lines[start + 1:end]
    if line.startswith("COPY ")
}
expected = {
    "/build_files/base/21-container-native-iso.sh",
    "/build_files/shared/utils/ghcurl",
}
if copies != expected:
    print(f"unexpected ctx-iso inputs: {sorted(copies ^ expected)}", file=sys.stderr)
    raise SystemExit(1)

iso_mounts = [
    line for line in lines
    if "source=/build_files/base/21-container-native-iso.sh" in line
    or "source=/build_files/shared/utils/ghcurl" in line
]
if len(iso_mounts) != 2 or any("from=ctx-iso" not in line for line in iso_mounts):
    print("ISO inputs must mount from ctx-iso", file=sys.stderr)
    raise SystemExit(1)
' "${CONTAINERFILE}"

    [ "$status" -eq 0 ]
}
