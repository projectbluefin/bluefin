---
name: setup-hook-tests
version: "1.1"
last_updated: "2026-08-07"
id: setup-hook-tests
one_line_purpose: Add or extend Bats coverage for setup-hook and build scripts.
entry_point: docs/skills/setup-hook-tests/SKILL.md
category: test-authoring
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [testing, bats, setup-hooks, sandbox]
description: >-
  Describes the Bats sandbox layout, path patching, and command stubbing
  used to test setup hooks in tests/unit. Use when adding or changing
  coverage for a system_files setup hook or a build_files script.
metadata:
  type: procedure
  source-of-truth:
    - tests/unit/
    - tests/coverage/
    - system_files/shared/usr/share/ublue-os/
    - .github/workflows/pr-validation.yml
---

# Setup-hook tests

## When to Use

- Adding or changing Bats coverage for a `system_files` setup hook
  (`privileged-setup.hooks.d/` or `user-setup.hooks.d/`).
- Adding coverage for a `build_files/` shell script — the same sandbox
  conventions apply.

## When Not to Use

- Full image validation or E2E behavior: use [build](../build/SKILL.md) and
  [ci](../ci/SKILL.md).
- Factory-wide shell authoring rules: see
  [common shell-scripts](https://github.com/projectbluefin/common/blob/main/docs/skills/shell-scripts.md).

## Core Process

1. Append to the existing test file for the script. The naming convention is
   `tests/unit/<script-stem>_test.bats` — one file per script under test.
2. In `setup()`, derive `SCRIPT_DIR` from `$BATS_TEST_FILENAME` and create a
   unique sandbox under `tests/unit/.bats-sandbox/<name>.${BATS_TEST_NUMBER}.$$`.
3. Stub every external command through a test-local `stub-bin` directory
   prepended to `PATH`. Log the stub's arguments so the assertion can inspect
   them.
4. Patch absolute system paths before running the script — for example, `sed`
   the `source /usr/lib/ublue/setup-services/libsetup.sh` line into a no-op
   `version-script()` stub, and write the patched copy into the sandbox.
5. Run the patched copy with `run bash "${PATCHED_SCRIPT}"`.
6. Assert the concrete side effect (a stub log line, a created file, an option
   value), not only the exit status.
7. Remove the sandbox in `teardown()`.

Run:

```bash
bats tests/unit/
python3 -m unittest discover -s tests -p 'test_*.py'
pre-commit run --all-files
```

## How CI runs these

The `unit-tests` job in `.github/workflows/pr-validation.yml` runs
`bats --formatter tap tests/unit/` and owns pass/fail, then reruns the suite
under kcov to publish the `bats-tap-results` and `bats-kcov-report` artifacts.
Coverage is collected through the `tests/coverage/bin/bash` wrapper, so a test
that `source`s a library into the BATS process itself is not traced — prefer
`run bash <script>` when coverage matters. See
[ci failure modes](../ci/references/failure-modes.md).

## Red Flags

- Writing outside the test's own sandbox, or reusing a fixed sandbox path.
- Calling a real `/usr` helper or an absolute binary path instead of a stub.
- Asserting only that the script exited zero.
- Creating a second test file for a script that already has one.
- Leaving the sandbox behind because `teardown()` is missing.
- `source`ing the script under test and then expecting kcov coverage for it.

## Verification

```bash
# Current test inventory and the naming convention
ls tests/unit/

# Sandbox and stub conventions in use
grep -n 'bats-sandbox\|STUB_BIN\|PATCHED_SCRIPT' tests/unit/10-tailscale_test.bats

# Hooks that need coverage
ls system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/ \
   system_files/shared/usr/share/ublue-os/user-setup.hooks.d/

# The job that runs them
sed -n '/unit-tests:/,/testsuite:/p' .github/workflows/pr-validation.yml
```
