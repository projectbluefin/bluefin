# e01s01: Add compact agent entry point and skill index

## 1. Type

Documentation feature.

## 2. Risk

P2: agent navigation changes with no runtime behavior change.

## 3. Context

Agents currently receive duplicated root and client-specific instructions.

## 4. Problem

The task router and agent contract are too large and inconsistent.

## 5. Users

Coding agents and maintainers selecting repository guidance.

## 6. Value

A small first load directs an agent to one relevant skill.

## 7. Scope

Rewrite `AGENTS.md`; add `docs/README.md` and `docs/skills/index.md`.

## 8. Requirements

### ADDED: Compact agent navigation

The root agent file must route through the skill index and preserve safety and
source-of-truth rules without duplicating full procedures.

## 9. Assumptions

The repository uses standard Markdown and directory-local skill files.

## 10. Dependencies

Existing source files and workflow paths.

## 11. Constraints

`AGENTS.md` ≤150 lines; skill index ≤80 lines.

## 12. Implementation steps

1. Rewrite the root entry point → verify: `test -f AGENTS.md && test $(wc -l < AGENTS.md) -le 150`
2. Add the indexes → verify: `python3 .github/scripts/validate-docs.py`

## 13. Verification

Run the default pre-commit gate and documentation validator.

## 14. Acceptance criteria

```gherkin
Scenario: Agent selects a task skill
  Given the repository root is loaded
  When an agent reads AGENTS.md and docs/skills/index.md
  Then it can select a matching skill without loading every skill

Scenario: Safety rules remain discoverable
  Given an agent is preparing a change
  When it reads AGENTS.md
  Then source-of-truth and staging safeguards are visible
```

## 15. Edge cases

A missing or unindexed skill must fail documentation validation.

## 16. Out of scope

Changing image, CI, or release behavior.

## 17. Risks

Over-compression could hide a safety rule; preserve concrete commands.

## 18. Rollback

Restore the prior root router and remove the new index files.

## 19. Completion evidence

`validate-docs.py`, pre-commit, and `just check` pass.

## 20. Status

Complete.
