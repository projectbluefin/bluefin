---
name: ci
description: Debug and change repository CI workflows. Use for triggers, checks, promotion, release, or workflow failures.
metadata:
  source-of-truth:
    - .github/workflows/
    - .github/workflows/pr-validation.yml
    - .github/workflows/build-image-testing.yml
---

# CI

## When to Use

- A workflow failed, did not start, or ran the wrong checks.
- A trigger, permission, path filter, or reusable workflow call changes.

## When NOT to Use

- The issue is purely local validation: use [build](../build/SKILL.md).
- The change is package placement: use [packages](../packages/SKILL.md).
- The change is release procedure: use [release-artifacts](../release-artifacts/SKILL.md).

## Core Process

1. Read the actual workflow before describing or changing its behavior.
2. Inspect recent runs when debugging:

   ```bash
   gh run list --repo projectbluefin/bluefin --limit 20
   gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
   gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
   ```

3. Identify the owning reusable workflow; callers should stay thin.
4. Verify the pull request base branch when debugging missing checks.
5. Preserve action pinning, permissions, and configured events.
6. Do not add PAT-based authentication.

For a completed run:

```bash
gh run watch RUN_ID --repo projectbluefin/bluefin --exit-status
```

## Verification

```bash
actionlint .github/workflows/*.yml
just check
pre-commit run --all-files
```

- [ ] The affected YAML and owning workflow were read.
- [ ] The skill was updated when workflow behavior changed.

## References

- [workflow reference](references/workflow-map.md)
- [failure modes](references/failure-modes.md)

## Common Rationalizations

- “A shortcut is harmless.” Preserve the configured workflow boundary.

## Red Flags

- Changing a caller when behavior belongs in reusable workflow logic.
- Rerunning or weakening a check without understanding its trigger.
