---
name: setup-hook-tests
version: "1.0"
last_updated: 2026-08-06
id: setup-hook-tests
one_line_purpose: Add or extend Bats coverage for setup-hook scripts.
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
  coverage for a system_files setup hook.
metadata:
  type: procedure
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
