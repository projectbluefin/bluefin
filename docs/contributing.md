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
- Check for an existing pull request before opening a new one:
  `gh pr list --repo projectbluefin/bluefin --state open --search "<topic>"`.
- Use squash merging.
- Use Conventional Commits for titles and commits.
- Keep one logical change per pull request.
- Link the issue with `Closes #NNN`.
- Do not include secrets or generated artifacts, and never add a new secret,
  token, or credential — that is a human decision.
- Describe exactly what was tested.
- Update the closest skill when the change reveals a reusable procedure.
- Do not self-approve or self-merge.

AI-assisted commits must include both attribution trailers:

```text
Assisted-by: <Model> via GitHub Copilot
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

## Scope discipline

Read the affected source before changing documentation. Shared behavior belongs
in its shared source; do not duplicate implementation in a caller or a skill.
