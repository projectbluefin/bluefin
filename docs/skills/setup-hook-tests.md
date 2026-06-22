---
name: setup-hook-tests
description: Add or extend Bats coverage for setup hook scripts. Use when touching tests/unit/*hook*_test.bats, user-setup hooks, privileged-setup hooks, or patching hook scripts for unit tests.
metadata:
  context7-sources:
    - /bats-core/bats-core
---

# Setup Hook Bats Tests

## When to Use

- Adding tests for `system_files/shared/usr/share/ublue-os/user-setup.hooks.d/*.sh`
- Adding tests for `system_files/shared/usr/share/ublue-os/privileged-setup.hooks.d/*.sh`
- Extending `tests/unit/*_test.bats` for hook edge cases

## When NOT to Use

- Testing `build_files/**` helpers without hook-specific path patching
- Full image or workflow validation work
- Refactoring hook scripts themselves without changing test coverage

## Core Process

1. Append to the existing hook test file in `tests/unit/`; do not create a second file for the same hook.
2. In `setup()`, create the sandbox at `${SCRIPT_DIR}/.bats-sandbox/<name>.<test_num>.$$`, add `stub-bin/`, and prepend it to `PATH`.
3. Patch hook scripts with `sed` before running them:
   - replace `source /usr/lib/ublue/setup-services/libsetup.sh` with `version-script() { return 0; }`
   - replace absolute system paths (`/usr/libexec/...`, `/var/lib/...`, `/sys/...`, `/usr/share/...`) with sandbox paths
   - replace absolute command paths like `/usr/bin/cp` if the test needs a stubbed command
4. Run imperative hooks with Bats `run`, then assert on `$status` and `$output`:
   ```bash
   run bash "${PATCHED_SCRIPT}"
   [ "$status" -eq 0 ]
   [[ "$output" == *"Warning:"* ]]
   ```
5. Assert the real side effect that would catch a regression: file mode, idempotent config line count, skipped branch, or non-zero exit propagation.

## Common Rationalizations

- "A happy-path install test is enough."
  Edge branches in hooks are where regressions hide; add the branch that would actually crash, duplicate config, or ignore a failure.

- "I can call the real system path."
  Hook tests must stay sandboxed; patch absolute paths or the test stops being deterministic.

- "I'll add a new test file for one edge case."
  Keep one test file per hook so coverage stays discoverable and CI stays boring.

## Red Flags

- Tests write outside `${SCRIPT_DIR}/.bats-sandbox/...`
- A hook test sources real `/usr/lib/...` helpers
- Assertions only check "exit 0" without validating the branch effect
- A patched hook still calls an unstubbed absolute binary path

## Verification

- [ ] Added coverage only in the existing hook test file
- [ ] Sandbox path follows `${SCRIPT_DIR}/.bats-sandbox/<name>.<test_num>.$$`
- [ ] Absolute paths were patched to sandbox or stubbed commands
- [ ] Tests assert on `$status`, `$output`, or concrete file side effects
- [ ] `bats tests/unit/` passes
- [ ] `just check && pre-commit run --all-files` passes before commit

## Sources

- Context7: `/bats-core/bats-core` — `setup`/`teardown` hooks and `run` status/output assertions
