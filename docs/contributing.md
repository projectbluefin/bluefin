# Contributing

## Before editing

Read [`../AGENTS.md`](../AGENTS.md), then select one matching skill from
[`skills/index.md`](skills/index.md). Read the affected source before changing
its documentation.

## Required local checks

```bash
just check
pre-commit run --all-files
```

For shell-library or setup-hook changes:

```bash
bats tests/unit/
```

For workflow changes:

```bash
actionlint .github/workflows/*.yml
```

Run a full image build only when image assembly or image contents changed.

## Pull requests

- Target `testing` for normal feature pull requests; do not target `main`.
- Use squash merging.
- Use Conventional Commits for titles and commits.
- Keep one logical change per pull request.
- Do not include secrets or generated artifacts.
- Describe exactly what was tested.
- Update the closest skill when a change reveals a reusable procedure.

## Scope discipline

Shared behavior belongs in its source of truth. Do not duplicate implementation
or mutable policy in a caller, guide, or skill. Documentation-only changes use
the normal review path but should not trigger expensive image builds.
