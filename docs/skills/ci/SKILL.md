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

## Use when

- A workflow failed, did not start, or ran the wrong checks.
- A trigger, permission, path filter, or reusable workflow call changes.

## Do not use when

- The issue is purely local validation: use [build](../build/SKILL.md).
- The change is package placement: use [packages](../packages/SKILL.md).
- The change is release procedure: use [release-artifacts](../release-artifacts/SKILL.md).

## First checks

```bash
gh run list --repo projectbluefin/bluefin --limit 20
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
```

Read the actual workflow before describing or changing its behavior. Shared
logic belongs in the reusable workflow that owns it; callers should stay thin.

## Hard rules

- Verify the pull request base branch before debugging missing checks.
- Preserve action pinning and workflow permissions.
- Do not add PAT-based authentication.
- Keep end-to-end suites on their configured event.
- Update this skill when workflow behavior changes.

## Verification

```bash
actionlint .github/workflows/*.yml
just check
pre-commit run --all-files
```

For a completed run:

```bash
gh run watch RUN_ID --repo projectbluefin/bluefin --exit-status
```

## References

- [workflow reference](references/workflow-map.md)
- [failure modes](references/failure-modes.md)
