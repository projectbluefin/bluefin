# Skill index

Load one matching skill. Load a linked reference only when the selected skill
requires details that are not in its summary.

| Task signal | Skill | Source of truth |
|---|---|---|
| Build or validate image changes | [build](build/SKILL.md) | `Containerfile`, `Justfile`, `build_files/`, `tests/` |
| Debug workflows or change CI | [ci](ci/SKILL.md) | `.github/workflows/` |
| Change dependency automation | [dependency-automation](dependency-automation/SKILL.md) | automation config and workflows |
| Work on installation artifacts | [installation-artifacts](installation-artifacts/SKILL.md) | installation workflows and build files |
| Understand issue state | [issue-lifecycle](issue-lifecycle/SKILL.md) | lifecycle workflow |
| Change package inputs | [packages](packages/SKILL.md) | package build files and `Justfile` |
| Prepare a release | [release-artifacts](release-artifacts/SKILL.md) | release workflows |
| Review supply-chain behavior | [security](security/SKILL.md) | package, signing, and verification source |
| Add setup-hook tests | [setup-hook-tests](setup-hook-tests/SKILL.md) | `system_files/`, `tests/unit/` |
| Improve or add a skill | [skill-improvement](skill-improvement/SKILL.md) | `AGENTS.md`, this index, validator |
| Understand image streams | [variants](variants/SKILL.md) | `Justfile`, image metadata, workflows |

## Selection rules

- Prefer the smallest matching skill.
- Do not load every skill directory.
- Follow references only when the selected skill links them.
- Update the closest skill when a reusable fact or procedure changes.
