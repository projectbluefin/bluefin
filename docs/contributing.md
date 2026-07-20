# Contributing

## Before editing

Read [`../AGENTS.md`](../AGENTS.md), then load the matching skill from
[`skills/index.md`](skills/index.md). Start from the remote `testing` branch, not an unrelated local commit.

## Required local checks

```bash
just check
pre-commit run --all-files
```

For shell-library or setup-hook changes:

```bash
bats tests/unit/
```

Run a full image build only when the change affects image assembly.

## Pull requests

- Target `testing`; do not target `main` for normal feature work.
- Use squash merging.
- Use Conventional Commits for titles and commits.
- Keep one logical change per pull request.
- Do not include secrets or generated artifacts.
- Describe exactly what was tested.
- Update the closest skill when the change reveals a reusable procedure.

AI-assisted commits must include the repository's required attribution trailer.

## Scope discipline

Read the affected source before changing documentation. Shared behavior belongs
in its shared source; do not duplicate implementation in a caller or a skill.
