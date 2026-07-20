# Skill index

Load exactly one task skill when possible. Load a referenced document only when
the selected skill directs you to do so.

| Task | Skill |
|---|---|
| Build or validate image changes | [build](build/SKILL.md) |
| Debug workflows | [ci](ci/SKILL.md) |
| Change package inputs | [packages](packages/SKILL.md) |
| Review supply-chain behavior | [security](security/SKILL.md) |
| Prepare a release | [release-artifacts](release-artifacts/SKILL.md) |
| Understand image streams | [variants](variants/SKILL.md) |
| Add setup-hook tests | [setup-hook-tests](setup-hook-tests/SKILL.md) |
| Handle dependency automation | [dependency-automation](dependency-automation/SKILL.md) |
| Understand issue state | [issue-lifecycle](issue-lifecycle/SKILL.md) |
| Work on installation artifacts | [installation-artifacts](installation-artifacts/SKILL.md) |
| Improve or add a skill | [skill-improvement](skill-improvement/SKILL.md) |

## Rules

- Prefer one matching skill; do not load the whole directory.
- Read source-of-truth files before documenting mutable behavior.
- Follow references only for details needed by the current task.
- Update the closest skill when a reusable fact or procedure changes.
