# Repository documentation

This directory contains the canonical technical and agent-facing documentation.

## Start here

- Agents: [`../AGENTS.md`](../AGENTS.md)
- Skill routing: [`skills/index.md`](skills/index.md)
- Contributors: [`contributing.md`](contributing.md)
- Architecture: [`architecture.md`](architecture.md)
- Validation: [`qa.md`](qa.md)
- Releases: [`release.md`](release.md)
- Issue lifecycle: [`workflow.md`](workflow.md)

## Documentation policy

Source files and workflows are authoritative. Documentation summarizes stable
procedures and links to source for mutable facts. Load only the document needed
for the current task; detailed references live below individual skills.

Cross-repo factory procedure is canonical in
[`projectbluefin/common`](https://github.com/projectbluefin/common/blob/main/docs/factory/agentic-model.md).
Link to it rather than restating it here.

`SKILL.md`, `build.md`, `ci.md`, and `pr-checklist.md` in this directory are
compatibility pointers for older inbound links; they only redirect.
