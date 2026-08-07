# Skill index

Load exactly one task skill when possible. Load a referenced document only when
the selected skill directs you to do so.

| Task | Skill |
|---|---|
| Do all feature work in isolated git worktrees | [worktrees](worktrees/SKILL.md) |
| Build, validate, and test image changes locally before pushing | [build](build/SKILL.md) |
| Debug and change repository GitHub Actions workflows | [ci](ci/SKILL.md) |
| Add, remove, or classify RPM, Flatpak, COPR, and Homebrew inputs | [packages](packages/SKILL.md) |
| Review supply-chain, signing, COPR, and secure-boot changes | [security](security/SKILL.md) |
| Prepare, verify, and troubleshoot image release and promotion | [release-artifacts](release-artifacts/SKILL.md) |
| Determine the correct image, stream, flavor, branch, and target | [variants](variants/SKILL.md) |
| Add or extend Bats coverage for setup-hook and build scripts | [setup-hook-tests](setup-hook-tests/SKILL.md) |
| Review Renovate configuration and automated dependency updates | [dependency-automation](dependency-automation/SKILL.md) |
| Operate the repository issue lifecycle and work queue correctly | [issue-lifecycle](issue-lifecycle/SKILL.md) |
| Locate the installation media that consumes a published image | [installation-artifacts](installation-artifacts/SKILL.md) |
| Maintain and refactor agent skills without duplicating facts | [skill-improvement](skill-improvement/SKILL.md) |
| Author a new skill directory that satisfies this repository's front-matter contract | [write-a-skill](write-a-skill/SKILL.md) |

## Rules

- Prefer one matching skill; do not load the whole directory.
- Read source-of-truth files before documenting mutable behavior.
- Follow references only for details needed by the current task.
- Update the closest skill when a reusable fact or procedure changes.
