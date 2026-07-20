# Repository agent guide

## Purpose

This repository builds and validates a bootable OCI desktop image.

Use source files and workflows as the authority. Documentation explains stable
invariants and routes agents to the smallest relevant procedure.

## Fast path

1. Read this file.
2. Read [`docs/skills/index.md`](docs/skills/index.md).
3. Select the smallest matching skill.
4. Read that skill's `SKILL.md`.
5. Read linked references only when the skill requires them.
6. Inspect the listed source-of-truth files before editing.

## Canonical guides

- [Architecture](docs/architecture.md)
- [Contributing](docs/contributing.md)
- [Quality and validation](docs/qa.md)
- [Release model](docs/release.md)
- [Workflow](docs/workflow.md)

## Common commands

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

Build an image only when image assembly or image contents changed:

```bash
just build <image> <stream> <flavor>
just clean
```

For documentation changes, run:

```bash
python3 .github/scripts/validate-docs.py
pre-commit run --all-files
```

## Source of truth

- `Containerfile`: image stages and assembly
- `Justfile`: local operator commands
- `build_files/`: build logic
- `system_files/`: installed files and hooks
- `tests/`: executable regression coverage
- `.github/workflows/`: CI and release behavior
- `docs/skills/`: task-specific agent procedures

When documentation disagrees with source, source wins. Update the closest
canonical document when a stable fact changes.

## Boundaries

- Do not modify generated artifacts, caches, or worktrees.
- Do not add secrets, credentials, private keys, or personal infrastructure.
- Read affected workflows before changing CI or release behavior.
- Do not weaken package-source, signing, or verification boundaries.
- Do not run expensive image builds for documentation-only changes.
- Do not create client-specific or tool-specific instruction duplicates.
- Do not use destructive git commands.
- Never use `git add -A` or `git add .`.
- Keep each change focused and report exact validation commands.

## Documentation write-back

When a change reveals a reusable procedure or invariant:

1. Load [`docs/skills/skill-improvement/SKILL.md`](docs/skills/skill-improvement/SKILL.md).
2. Confirm the fact against source or an authoritative external document.
3. Update the closest canonical skill or guide in the same change.
4. Add or update its verification command.
5. Run documentation validation and relevant repository checks.
