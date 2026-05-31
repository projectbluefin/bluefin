# docs/skills — In-Repo Skill References

Condensed guidance for contributors and agents working in Bluefin.
Read the matching file before making changes in that area.

## Routing Table

| Task | Load |
|---|---|
| I need to build, validate, or open a PR | [build.md](build.md) |
| I need to add, remove, or update packages | [packages.md](packages.md) |
| I need to debug GitHub Actions or promotions | [ci.md](ci.md) |
| I need the current image × tag × flavor matrix | [variants.md](variants.md) |
| I need release or stream promotion workflow details | [release.md](release.md) |
| I need to handle a Renovate PR or config change | [renovate.md](renovate.md) |
| I need security rules for COPR, cosign, or secureboot | [security.md](security.md) |
| I need Bluefin LTS guidance | [lts.md](lts.md) |
| I need ISO build or promotion guidance | [iso.md](iso.md) |

## How to extend these files

1. Update the closest matching skill file.
2. Keep it short, command-heavy, and repo-specific.
3. Add reusable fixes under `## Lessons learned`.
4. Do not add personal hostnames, private infrastructure, or one-off session notes.
