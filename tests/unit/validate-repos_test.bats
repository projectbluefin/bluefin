#!/usr/bin/env bats
# Unit tests for build_files/shared/validate-repos.sh.
# Run with: bats tests/unit/validate-repos_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
VALIDATE_REPOS_LIB="${SCRIPT_DIR}/../../build_files/shared/validate-repos.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/validate-repos.${BATS_TEST_NUMBER:-0}.$$"
    mkdir -p "${TEST_ROOT}"

    ENABLED_REPOS=()
    VALIDATION_FAILED=0

    eval "$(sed -n '/^check_repo_file() {/,/^}/p' "${VALIDATE_REPOS_LIB}")"
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

@test "check_repo_file: valid disabled repo file reports disabled" {
    repo_file="${TEST_ROOT}/valid.repo"
    output_file="${TEST_ROOT}/output.txt"
    cat > "${repo_file}" <<'EOF'
[test-repo]
name=Test Repo
enabled=0
EOF

    check_repo_file "${repo_file}" > "${output_file}"
    output="$(<"${output_file}")"

    [ "${VALIDATION_FAILED}" -eq 0 ]
    [ "${#ENABLED_REPOS[@]}" -eq 0 ]
    [[ "${output}" == *"Disabled: valid.repo"* ]]
}

@test "check_repo_file: enabled repo file marks validation failed and reports section" {
    repo_file="${TEST_ROOT}/enabled.repo"
    output_file="${TEST_ROOT}/output.txt"
    cat > "${repo_file}" <<'EOF'
[test-repo]
name=Test Repo
enabled=1
EOF

    check_repo_file "${repo_file}" > "${output_file}"
    output="$(<"${output_file}")"

    [ "${VALIDATION_FAILED}" -eq 1 ]
    [ "${#ENABLED_REPOS[@]}" -eq 1 ]
    [ "${ENABLED_REPOS[0]}" = "enabled.repo" ]
    [[ "${output}" == *"ENABLED: enabled.repo"* ]]
    [[ "${output}" == *"- [test-repo]"* ]]
}

@test "check_repo_file: missing file is skipped" {
    missing_file="${TEST_ROOT}/missing.repo"
    output_file="${TEST_ROOT}/output.txt"

    check_repo_file "${missing_file}" > "${output_file}"
    output="$(<"${output_file}")"

    [ "${VALIDATION_FAILED}" -eq 0 ]
    [ "${#ENABLED_REPOS[@]}" -eq 0 ]
    [ -z "${output}" ]
}

@test "check_repo_file: empty or malformed content without enabled repos stays disabled" {
    repo_file="${TEST_ROOT}/malformed.repo"
    output_file="${TEST_ROOT}/output.txt"
    cat > "${repo_file}" <<'EOF'
this is not a repo file
enabled = maybe
EOF

    check_repo_file "${repo_file}" > "${output_file}"
    output="$(<"${output_file}")"

    [ "${VALIDATION_FAILED}" -eq 0 ]
    [ "${#ENABLED_REPOS[@]}" -eq 0 ]
    [[ "${output}" == *"Disabled: malformed.repo"* ]]
}
