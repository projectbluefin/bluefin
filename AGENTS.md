# AGENTS.md

## Purpose

This repository builds and validates a bootable OCI desktop image. Start here,
then load only the documentation needed for the task.

## Documentation navigation

1. Read this file.
2. Read [`docs/skills/index.md`](docs/skills/index.md).
3. Load one matching `docs/skills/<name>/SKILL.md`.
4. Load linked references only when the selected skill requires them.
5. Treat source files and workflow definitions as authoritative over summaries.

Stable guidance:

- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Contribution policy: [`docs/contributing.md`](docs/contributing.md)
- Validation and QA: [`docs/qa.md`](docs/qa.md)
- Release model: [`docs/release.md`](docs/release.md)
- Issue lifecycle: [`docs/workflow.md`](docs/workflow.md)

## Common validation

Run the lightest relevant checks:

```bash
just check
pre-commit run --all-files
```

For shell-library or setup-hook changes:

```bash
bats tests/unit/
```

Run a full image build only when image assembly or container behavior changed:

```bash
just build <image> <stream> <flavor>
just clean
```

Install the repository hook once after cloning:

```bash
bash .github/scripts/install-hooks.sh
```

## Source-of-truth rules

- `Justfile` defines local commands.
- `Containerfile` defines image stages.
- `build_files/` defines build logic.
- `.github/workflows/` defines CI and release triggers.
- `tests/` defines executable regression coverage.
- Documentation must not contradict source files.
- If behavior changes, update the closest matching skill in the same change.

## Boundaries

- Do not modify generated artifacts, caches, or worktree contents.
- Do not add secrets, credentials, or personal infrastructure details.
- Do not change CI or release behavior without reading the affected workflow.
- Do not weaken package-source, signing, or verification boundaries.
- Do not run expensive image builds for documentation-only changes.
- Never use `git add -A` or `git add .`; stage only intended paths and inspect
  `git diff --cached --name-only` before committing.
- Keep documentation generic, source-linked, and reusable.
- Do not create client-specific agent instructions or tool-specific duplicates.

## Completion

Before declaring work complete:

1. Run relevant validation commands.
2. Check links and changed paths.
3. Update the matching skill when a reusable fact or procedure changes.
4. Keep the change narrowly scoped.
