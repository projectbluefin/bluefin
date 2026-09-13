#!/usr/bin/env bats
# Unit tests for ujust completion scripts (bash and zsh).

setup() {
    TEST_DIR="${BATS_TEST_TMPDIR:-/tmp}/ujust-completion-test.$$"
    mkdir -p "${TEST_DIR}/usr/share/ublue-os/just"
    mkdir -p "${TEST_DIR}/bin"

    # Create mock 00-entry.just
    cat > "${TEST_DIR}/usr/share/ublue-os/just/00-entry.just" <<'EOF'
# Sample entry justfile for ujust tests
update:
	echo "updating"

clean-system:
	echo "cleaning system"

configure:
	echo "configuring"

toggle-updates:
	echo "toggling updates"
EOF

    # Create mock just binary
    cat > "${TEST_DIR}/bin/just" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == *"--summary"* ]]; then
    echo "clean-system configure toggle-updates update"
    exit 0
fi
exit 0
EOF
    chmod +x "${TEST_DIR}/bin/just"

    BASH_COMPLETION_SRC="${BATS_TEST_DIRNAME}/../../system_files/shared/usr/share/bash-completion/completions/ujust"
    ZSH_COMPLETION_SRC="${BATS_TEST_DIRNAME}/../../system_files/shared/usr/share/zsh/site-functions/_ujust"

    # Prepare patched bash completion pointing to TEST_DIR
    PATCHED_BASH_COMP="${TEST_DIR}/ujust_bash"
    sed "s|/usr/share/ublue-os/just/00-entry.just|${TEST_DIR}/usr/share/ublue-os/just/00-entry.just|g" \
        "${BASH_COMPLETION_SRC}" > "${PATCHED_BASH_COMP}"

    export TEST_DIR PATH="${TEST_DIR}/bin:${PATH}"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

@test "ujust bash completion: completes available recipes when no prefix provided" {
    run bash -c "
        export PATH=\"${TEST_DIR}/bin:\$PATH\"
        source \"${PATCHED_BASH_COMP}\"
        COMP_WORDS=(ujust '')
        COMP_CWORD=1
        COMP_LINE='ujust '
        COMP_POINT=6
        COMPREPLY=()
        _ujust
        echo \"\${COMPREPLY[*]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"update"* ]]
    [[ "$output" == *"clean-system"* ]]
    [[ "$output" == *"configure"* ]]
    [[ "$output" == *"toggle-updates"* ]]
}

@test "ujust bash completion: completes recipe matching prefix 'up'" {
    run bash -c "
        export PATH=\"${TEST_DIR}/bin:\$PATH\"
        source \"${PATCHED_BASH_COMP}\"
        COMP_WORDS=(ujust 'up')
        COMP_CWORD=1
        COMP_LINE='ujust up'
        COMP_POINT=8
        COMPREPLY=()
        _ujust
        echo \"\${COMPREPLY[*]}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "update" ]
}

@test "ujust bash completion: completes recipe matching prefix 'cl'" {
    run bash -c "
        export PATH=\"${TEST_DIR}/bin:\$PATH\"
        source \"${PATCHED_BASH_COMP}\"
        COMP_WORDS=(ujust 'cl')
        COMP_CWORD=1
        COMP_LINE='ujust cl'
        COMP_POINT=8
        COMPREPLY=()
        _ujust
        echo \"\${COMPREPLY[*]}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "clean-system" ]
}

@test "ujust bash completion: completes CLI options when prefix starts with '-'" {
    run bash -c "
        export PATH=\"${TEST_DIR}/bin:\$PATH\"
        source \"${PATCHED_BASH_COMP}\"
        COMP_WORDS=(ujust '--c')
        COMP_CWORD=1
        COMP_LINE='ujust --c'
        COMP_POINT=9
        COMPREPLY=()
        _ujust
        echo \"\${COMPREPLY[*]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--choose"* ]]
    [[ "$output" != *"update"* ]]
}

@test "ujust zsh completion: file exists and contains recipe completion logic" {
    [ -f "${ZSH_COMPLETION_SRC}" ]
    grep -q '#compdef ujust' "${ZSH_COMPLETION_SRC}"
    grep -q -- '--summary' "${ZSH_COMPLETION_SRC}"
    grep -q '/usr/share/ublue-os/just/00-entry.just' "${ZSH_COMPLETION_SRC}"
}
