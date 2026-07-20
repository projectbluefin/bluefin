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
