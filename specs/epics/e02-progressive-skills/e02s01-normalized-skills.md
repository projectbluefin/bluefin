# e02s01: Convert existing skills to normalized SKILL.md files

## 1. Type

Documentation migration.

## 2. Risk

P1: broad agent-facing navigation migration.

## 3. Context

Existing skills are flat files with inconsistent metadata and duplicated prose.

## 4. Problem

Agents cannot reliably discover or lazily load skill content.

## 5. Users

Coding agents authoring or reviewing repository changes.

## 6. Value

Each capability has predictable metadata, scope, and verification guidance.

## 7. Scope

Create 11 skill directories and targeted reference files.

## 8. Requirements

### ADDED: Normalized skill contract

Every active skill has `SKILL.md` with `name`, `description`, use boundaries,
source-of-truth paths, and verification guidance.

## 9. Assumptions

YAML front matter is the adopted community convention for skill discovery.

## 10. Dependencies

The skill index and existing repository source paths.

## 11. Constraints

Primary skill files remain under 180 lines.

## 12. Implementation steps

1. Create skill directories → verify: `test "$(find docs/skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)" -gt 0`
2. Normalize metadata → verify: `python3 .github/scripts/validate-docs.py`
3. Move detail to references → verify: `test "$(find docs/skills -type d -name references | wc -l)" -gt 0`

## 13. Verification

Run documentation validation and pre-commit.

## 14. Acceptance criteria

```gherkin
Scenario: Skill is selected lazily
  Given the skill index lists a capability
  When an agent opens that capability
  Then only its SKILL.md is required before task execution

Scenario: Invalid metadata is rejected
  Given a skill lacks required front matter
  When documentation validation runs
  Then validation fails with the skill path
```

## 15. Edge cases

References may be large but must remain separately linkable.

## 16. Out of scope

Implementing an MCP server or proprietary skill loader.

## 17. Risks

Moving files can break links; the link validator covers local targets.

## 18. Rollback

Restore flat skill files and the prior router.

## 19. Completion evidence

11 skills validate with normalized metadata.

## 20. Status

Complete.
