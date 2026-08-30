#!/usr/bin/env bats
# Unit tests for build_files/shared/utils/ghcurl.
# Run with: bats tests/unit/ghcurl_test.bats
#
# ghcurl is the token-bearing curl wrapper used by 04-install-kernel-akmods.py,
# 05-override-install.sh, 21-container-native-iso.sh and shared/build.sh. Its
# security contract is the _is_github_host allowlist: the Authorization header
# must be attached to GitHub-owned hosts only, never to third-party hosts
# (CWE-201 token leakage).

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
GHCURL="${REPO_ROOT}/build_files/shared/utils/ghcurl"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/ghcurl.${BATS_TEST_NUMBER:-0}.$$"
    STUB_BIN="${TEST_ROOT}/stub-bin"
    SECRETS_DIR="${TEST_ROOT}/run/secrets"
    CURL_LOG="${TEST_ROOT}/curl.log"

    mkdir -p "${STUB_BIN}" "${SECRETS_DIR}"

    # Stub curl: record argv one-per-line so header/URL ordering is assertable.
    cat >"${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/bash
for arg in "$@"; do
    printf '%s\n' "$arg" >>"${CURL_LOG}"
done
printf 'STUB_CURL_OK\n'
EOF
    chmod +x "${STUB_BIN}/curl"

    # ── Patch the script ─────────────────────────────────────────────────────
    # Redirect the hardcoded Podman secret mount into the sandbox.
    PATCHED_GHCURL="${TEST_ROOT}/ghcurl"
    sed \
        -e "s|/run/secrets/GITHUB_TOKEN|${SECRETS_DIR}/GITHUB_TOKEN|g" \
        "${GHCURL}" > "${PATCHED_GHCURL}"
    chmod +x "${PATCHED_GHCURL}"

    export PATH="${STUB_BIN}:${PATH}"
    export CURL_LOG SECRETS_DIR PATCHED_GHCURL
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

write_token() {
    printf '%s' "${1:-s3cr3t-token}" >"${SECRETS_DIR}/GITHUB_TOKEN"
}

# Assert the stub curl received an Authorization header.
assert_auth_sent() {
    grep -Fxq "Authorization: Bearer s3cr3t-token" "${CURL_LOG}" || {
        echo "FAIL: expected Authorization header in curl argv:"
        cat "${CURL_LOG}"
        return 1
    }
    grep -Fxq -- "-H" "${CURL_LOG}" || {
        echo "FAIL: expected -H flag in curl argv:"
        cat "${CURL_LOG}"
        return 1
    }
}

# Assert no Authorization header (and no token substring) reached curl.
assert_no_auth_sent() {
    if grep -q "Authorization" "${CURL_LOG}"; then
        echo "FAIL: Authorization header leaked to curl argv:"
        cat "${CURL_LOG}"
        return 1
    fi
    if grep -q "s3cr3t-token" "${CURL_LOG}"; then
        echo "FAIL: token value leaked to curl argv:"
        cat "${CURL_LOG}"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Secret discovery
# ──────────────────────────────────────────────────────────────────────────────

@test "Missing GITHUB_TOKEN secret falls back to an unauthenticated request" {
    run "${PATCHED_GHCURL}" "https://github.com/projectbluefin/bluefin/file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GITHUB_TOKEN secret not found"* ]]
    [[ "$output" == *"STUB_CURL_OK"* ]]
    assert_no_auth_sent
}

@test "Present GITHUB_TOKEN secret is announced on stderr, never on stdout" {
    write_token
    run bash -c "'${PATCHED_GHCURL}' 'https://github.com/owner/repo' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = "STUB_CURL_OK" ]

    run bash -c "'${PATCHED_GHCURL}' 'https://github.com/owner/repo' 2>&1 >/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using GITHUB_TOKEN"* ]]
}

@test "Token value is never printed to stdout or stderr" {
    write_token
    run "${PATCHED_GHCURL}" "https://github.com/owner/repo"
    [ "$status" -eq 0 ]
    [[ "$output" != *"s3cr3t-token"* ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# _is_github_host allowlist — hosts that MUST receive the token
# ──────────────────────────────────────────────────────────────────────────────

@test "github.com receives the Authorization header" {
    write_token
    run "${PATCHED_GHCURL}" "https://github.com/projectbluefin/bluefin/raw/main/f"
    [ "$status" -eq 0 ]
    assert_auth_sent
}

@test "api.github.com subdomain receives the Authorization header" {
    write_token
    run "${PATCHED_GHCURL}" "https://api.github.com/repos/projectbluefin/bluefin"
    [ "$status" -eq 0 ]
    assert_auth_sent
}

@test "raw.githubusercontent.com receives the Authorization header" {
    write_token
    run "${PATCHED_GHCURL}" "https://raw.githubusercontent.com/o/r/main/f"
    [ "$status" -eq 0 ]
    assert_auth_sent
}

@test "ghcr.io receives the Authorization header" {
    write_token
    run "${PATCHED_GHCURL}" "https://ghcr.io/v2/projectbluefin/akmods/manifests/x"
    [ "$status" -eq 0 ]
    assert_auth_sent
}

@test "plain http GitHub URLs are matched by the allowlist" {
    write_token
    run "${PATCHED_GHCURL}" "http://github.com/owner/repo"
    [ "$status" -eq 0 ]
    assert_auth_sent
}

@test "Bare host URL with no path is matched by the allowlist" {
    write_token
    run "${PATCHED_GHCURL}" "https://github.com"
    [ "$status" -eq 0 ]
    assert_auth_sent
}

# ──────────────────────────────────────────────────────────────────────────────
# _is_github_host allowlist — hosts that MUST NOT receive the token (CWE-201)
# ──────────────────────────────────────────────────────────────────────────────

@test "Third-party host does not receive the Authorization header" {
    write_token
    run "${PATCHED_GHCURL}" "https://example.com/payload"
    [ "$status" -eq 0 ]
    assert_no_auth_sent
}

@test "Suffix-lookalike host github.com.evil.tld does not receive the token" {
    write_token
    run "${PATCHED_GHCURL}" "https://github.com.evil.tld/payload"
    [ "$status" -eq 0 ]
    assert_no_auth_sent
}

@test "Prefix-lookalike host notgithub.com does not receive the token" {
    write_token
    run "${PATCHED_GHCURL}" "https://notgithub.com/payload"
    [ "$status" -eq 0 ]
    assert_no_auth_sent
}

@test "Lookalike host evilghcr.io does not receive the token" {
    write_token
    run "${PATCHED_GHCURL}" "https://evilghcr.io/v2/x"
    [ "$status" -eq 0 ]
    assert_no_auth_sent
}

@test "Userinfo-smuggled host github.com@evil.tld does not receive the token" {
    write_token
    run "${PATCHED_GHCURL}" "https://github.com@evil.tld/payload"
    [ "$status" -eq 0 ]
    assert_no_auth_sent
}

@test "GitHub host in the path of a third-party URL does not receive the token" {
    write_token
    run "${PATCHED_GHCURL}" "https://evil.tld/https://github.com/owner/repo"
    [ "$status" -eq 0 ]
    assert_no_auth_sent
}

# ──────────────────────────────────────────────────────────────────────────────
# Argument forwarding
# ──────────────────────────────────────────────────────────────────────────────

@test "Caller options are forwarded ahead of the URL on the authenticated path" {
    write_token
    run "${PATCHED_GHCURL}" "https://github.com/o/r/f" -o /dev/null --retry 3
    [ "$status" -eq 0 ]
    run cat "${CURL_LOG}"
    [ "${lines[0]}" = "-sSL" ]
    [ "${lines[1]}" = "-H" ]
    [ "${lines[2]}" = "Authorization: Bearer s3cr3t-token" ]
    [ "${lines[3]}" = "-o" ]
    [ "${lines[4]}" = "/dev/null" ]
    [ "${lines[5]}" = "--retry" ]
    [ "${lines[6]}" = "3" ]
    [ "${lines[7]}" = "https://github.com/o/r/f" ]
}

@test "Caller options are forwarded ahead of the URL on the unauthenticated path" {
    run "${PATCHED_GHCURL}" "https://example.com/f" -o /dev/null
    [ "$status" -eq 0 ]
    run cat "${CURL_LOG}"
    [ "${lines[0]}" = "-sSL" ]
    [ "${lines[1]}" = "-o" ]
    [ "${lines[2]}" = "/dev/null" ]
    [ "${lines[3]}" = "https://example.com/f" ]
}

@test "curl always runs with -sSL so redirects are followed and errors surface" {
    run "${PATCHED_GHCURL}" "https://example.com/f"
    [ "$status" -eq 0 ]
    grep -Fxq -- "-sSL" "${CURL_LOG}"
}

@test "Arguments containing spaces survive forwarding as single arguments" {
    write_token
    run "${PATCHED_GHCURL}" "https://github.com/o/r/f" -o "${TEST_ROOT}/out file"
    [ "$status" -eq 0 ]
    grep -Fxq "${TEST_ROOT}/out file" "${CURL_LOG}"
}

@test "A URL-only invocation forwards no extra options" {
    run "${PATCHED_GHCURL}" "https://example.com/f"
    [ "$status" -eq 0 ]
    run wc -l <"${CURL_LOG}"
    [ "$output" -eq 2 ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Failure propagation
# ──────────────────────────────────────────────────────────────────────────────

@test "A curl failure propagates a non-zero exit status to the caller" {
    cat >"${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/bash
exit 22
EOF
    chmod +x "${STUB_BIN}/curl"
    run "${PATCHED_GHCURL}" "https://github.com/o/r/f"
    [ "$status" -eq 22 ]
}

@test "Invoking ghcurl with no URL fails instead of calling curl" {
    run "${PATCHED_GHCURL}"
    [ "$status" -ne 0 ]
    [ ! -f "${CURL_LOG}" ]
}
