# e02s02: Migrate links and remove duplicate instructions

## 1. Type

Documentation cleanup.

## 2. Risk

P1: repository-wide link and instruction removal.

## 3. Context

The client-specific instruction file duplicates the root agent contract.

## 4. Problem

Duplicate instructions can diverge and create client-specific behavior.

## 5. Users

All agents and maintainers using repository documentation.

## 6. Value

One portable agent contract and one canonical skill tree.

## 7. Scope

Migrate inbound links, delete flat skill duplicates, and remove the duplicate
client-specific instruction file.

## 8. Requirements

### MODIFIED: Agent instruction source

**Before:** Root and client-specific instruction files could diverge.

**After:** `AGENTS.md` is the portable root contract and skills are canonical.

## 9. Assumptions

All local Markdown links can be checked statically.

## 10. Dependencies

New skill directory paths and compatibility pointers.

## 11. Constraints

No broken local Markdown links after migration.

## 12. Implementation steps

1. Update inbound links → verify: `test -z "$(git grep -nE 'docs/skills/[a-z-]+\\.md|docs/SKILL\\.md' -- ':!specs/**' || true)"`
2. Delete duplicate instructions → verify: `test ! -e .github/copilot-instructions.md`
3. Validate local links → verify: `python3 .github/scripts/validate-docs.py`

## 13. Verification

Run pre-commit and inspect staged paths.

## 14. Acceptance criteria

```gherkin
Scenario: Agent uses one root contract
  Given the repository contains agent instructions
  When an agent starts work
  Then AGENTS.md and the skill index are the only required entry points

Scenario: Migration preserves links
  Given a Markdown document links to a moved skill
  When validation runs
  Then the link resolves to a current target
```

## 15. Edge cases

Compatibility pointers may remain only while they point to canonical documents.

## 16. Out of scope

Changing source or workflow behavior.

## 17. Risks

Deleting a duplicate can expose undocumented policy; review catches missing rules.

## 18. Rollback

Restore the prior files from the parent commit.

## 19. Completion evidence

No deprecated skill paths remain outside planning artifacts.

## 20. Status

Complete.
