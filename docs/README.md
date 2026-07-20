# Repository documentation

This directory contains canonical technical guides and task-specific agent
skills. Load only the document needed for the current task.

## Start here

- Agents: [`../AGENTS.md`](../AGENTS.md)
- Skill routing: [`skills/index.md`](skills/index.md)
- Contributors: [`contributing.md`](contributing.md)
- Architecture: [`architecture.md`](architecture.md)
- Validation: [`qa.md`](qa.md)
- Releases: [`release.md`](release.md)
- Workflow: [`workflow.md`](workflow.md)

## Documentation policy

Source files and workflows are authoritative. Documentation records stable
procedures, points to mutable sources, and avoids duplicating facts.

Skills use directory-local `SKILL.md` files. Load a skill only after selecting
it from the index; load its `references/` files only when the skill requires
the additional detail.
