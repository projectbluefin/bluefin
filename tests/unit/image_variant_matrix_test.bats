#!/usr/bin/env bats
#
# Gate: the published image-variant set is derived once, in the Justfile.
#
# `Justfile` declares the variant axes (`images`, `flavors`) and the
# `image_name` recipe turns a pair into a published image name. Five other
# sites restate the resulting set as literals. Nothing built the two together,
# so a new flavor could ship built-but-unscanned, or promoted-but-unreleased.
# These tests hold every restatement to the Justfile derivation.
#
# Sites covered:
#   .github/workflows/build-image-testing.yml   default image_flavors list
#   .github/workflows/execute-release.yml       variants matrix
#   .github/workflows/execute-release.yml       `for image in ...` digest loop
#   .github/workflows/execute-release.yml       release-notes variants table
#   .github/workflows/promote-testing-to-main.yml   variants matrix
#   .github/workflows/vulnerability-scan.yml    image_matrix

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HELPERS="${SCRIPT_DIR}/helpers"

@test "Justfile image_name recipe still matches the derivation helper" {
    run python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import variant_matrix as vm

vm.assert_image_name_rule()
if not vm.images() or not vm.flavors():
    raise SystemExit("Justfile variant axes are empty")
' "${HELPERS}"

    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "build-image-testing.yml default flavor list matches Justfile flavors" {
    run python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import variant_matrix as vm

text = vm.workflow("build-image-testing.yml")
declared = vm.json_literal_after(text, "|| ")
vm.compare(set(declared), set(vm.flavors()), "build-image-testing.yml image_flavors default")
' "${HELPERS}"

    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "execute-release.yml variants matrix matches the Justfile variant set" {
    run python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import variant_matrix as vm

text = vm.workflow("execute-release.yml")
vm.compare(vm.json_field_values(text, "image"), vm.variants(),
           "execute-release.yml variants matrix")
' "${HELPERS}"

    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "execute-release.yml digest loop iterates the Justfile variant set" {
    run python3 -c '
import re
import sys
sys.path.insert(0, sys.argv[1])
import variant_matrix as vm

text = vm.workflow("execute-release.yml")
match = re.search(r"for image in ([^;]+); do", text)
if match is None:
    raise SystemExit("execute-release.yml no longer has a `for image in ...` digest loop")
vm.compare(set(match.group(1).split()), vm.variants(),
           "execute-release.yml digest loop")
' "${HELPERS}"

    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "execute-release.yml release-notes table names every variant" {
    run python3 -c '
import re
import sys
sys.path.insert(0, sys.argv[1])
import variant_matrix as vm

text = vm.workflow("execute-release.yml")
start = text.find("## Variants promoted")
if start < 0:
    raise SystemExit("execute-release.yml no longer prepends a variants table")
end = text.find("printf", start)
table = text[start:end if end > start else len(text)]
rows = set(re.findall(r"\| \\`([a-z0-9.-]+)\\` \| \\`:", table))
vm.compare(rows, vm.variants(), "execute-release.yml release-notes variants table")
' "${HELPERS}"

    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "promote-testing-to-main.yml variants matrix matches the Justfile variant set" {
    run python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import variant_matrix as vm

text = vm.workflow("promote-testing-to-main.yml")
vm.compare(vm.json_field_values(text, "image"), vm.variants(),
           "promote-testing-to-main.yml variants matrix")
' "${HELPERS}"

    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "vulnerability-scan.yml image_matrix matches the Justfile variant set" {
    run python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import variant_matrix as vm

text = vm.workflow("vulnerability-scan.yml")
vm.compare(vm.json_field_values(text, "image_name"), vm.variants(),
           "vulnerability-scan.yml image_matrix")
' "${HELPERS}"

    [ "$status" -eq 0 ] || { echo "$output"; false; }
}
