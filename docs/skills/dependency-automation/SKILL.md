---
name: dependency-automation
version: "1.1"
last_updated: 2026-08-07
id: dependency-automation
one_line_purpose: Review Renovate configuration and automated dependency updates.
entry_point: docs/skills/dependency-automation/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [renovate, dependencies, automation, automerge]
description: >-
  Describes this repository's two Renovate configs, the automerge trigger, and
  the action-pinning hooks that constrain them. Use when changing dependency
  automation config or triaging an automated update pull request.
metadata:
  type: procedure
  source-of-truth:
    - renovate.json
    - .github/renovate.json5
    - .github/workflows/renovate-automerge.yml
    - .github/workflows/validate-renovate.yml
    - .pre-commit-config.yaml
---

# Dependency automation

## When to Use

- Changing `renovate.json`, `.github/renovate.json5`, or an automerge rule.
- Triaging a Renovate pull request that did not open, merge, or update.

## Do not use when

- Making a manual package change automation does not own: use
  [packages](../packages/SKILL.md).

## What the configuration actually says

Two files exist and both are live; read both before changing either.

- `renovate.json` extends `local>projectbluefin/renovate-config`, sets
  `baseBranchPatterns: ["testing"]`, automerges `digest`, `pin`, `patch`, and
  `minor` updates via `automergeType: pr` / `automergeStrategy: squash`, and
  **disables** the `github-actions` manager for `^projectbluefin/actions`.
- `.github/renovate.json5` extends `config:best-practices`, also pins
  `baseBranchPatterns: ["testing"]`, sets `rebaseWhen: "never"`, enables
  `git-submodules`, and carries the custom regex managers for `Justfile` image
  digests, `image-versions.yml` version and digest entries, and `.gitmodules`
  submodule release tags.

Renovate pull requests therefore target `testing`, never `main`.

## Why internal actions are excluded

Two local `pre-commit` hooks set the pinning policy that Renovate must respect:

- `no-floating-action-tags` blocks `@main`, `@master`, `@latest`, and `@v<N>`
  refs, **except** for `projectbluefin/actions`, `projectbluefin/bonedigger`,
  and `projectbluefin/testsuite`.
- `no-sha-pins-for-internal-actions` blocks 40-character SHA pins on
  `projectbluefin/actions` refs.

So third-party actions must be SHA-pinned and internal factory actions must use
the managed `@v1` tag. Renovate would fight the second hook, which is exactly
why `renovate.json` disables it for that package pattern. SHA-pinning policy is
canonical in
[`common/docs/skills/ci-tooling.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/ci-tooling.md).

## Automerge and validation triggers

- `renovate-automerge.yml` fires on `workflow_run` completion of
  `PR Validation — testsuite` and only when its conclusion is `success`. It
  calls `reusable-renovate-automerge.yml@v1` with the run's `head_sha`.
- `validate-renovate.yml` only watches `.github/renovate.json5` and
  `.github/workflows/renovate.yml`. It does **not** trigger on `renovate.json`,
  so a change there is not config-validated by CI — validate it locally.

## Procedure

1. Read both config files and the affected workflow.
2. Change the file that actually owns the rule; do not duplicate it.
3. Preserve the configured authentication model. Never add a personal access
   token or any other credential.
4. Confirm the pull request targets `testing`.
5. Run the gates.

```bash
just check
pre-commit run --all-files
npx --yes --package renovate -- renovate-config-validator renovate.json .github/renovate.json5
```

Do not document an automation rule until it is present in source configuration.

## Red Flags

- Adding a token, PAT, or app credential to make automation work.
- SHA-pinning a `projectbluefin/actions` ref, or floating a third-party action.
- Assuming CI validated `renovate.json`; only `.github/renovate.json5` is watched.
- Documenting a rule that is not in either config file.

## Verification

- [ ] `grep -n baseBranchPatterns renovate.json .github/renovate.json5` shows
      `testing` in both.
- [ ] `pre-commit run no-floating-action-tags no-sha-pins-for-internal-actions
      --all-files` passes.
- [ ] `just check` and `python3 .github/scripts/validate-docs.py` pass.
