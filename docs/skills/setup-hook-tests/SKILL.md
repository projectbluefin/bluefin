---
name: setup-hook-tests
description: Add or extend Bats coverage for setup-hook scripts.
metadata:
  source-of-truth:
    - tests/unit/
    - system_files/
---

# Setup-hook tests

## Procedure

1. Append to the existing test file for the hook.
2. Create a unique sandbox under `tests/unit/.bats-sandbox/`.
3. Patch absolute system paths before running the hook.
4. Stub commands through a test-local `stub-bin` directory.
5. Assert the concrete side effect, not only exit status.

Run:

```bash
bats tests/unit/
pre-commit run --all-files
```

## Red flags

- The test writes outside its sandbox.
- A real `/usr` helper or absolute binary is still called.
- A test asserts only that the script exits zero.
- A second test file is created for an existing hook.

## When to Use

Use for Bats coverage for setup hooks.

## When NOT to Use

Do not use for Non-hook build scripts or full image validation.

## Core Process

Sandbox the hook, patch absolute paths, assert concrete side effects.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Testing against the host filesystem or asserting only exit zero.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
