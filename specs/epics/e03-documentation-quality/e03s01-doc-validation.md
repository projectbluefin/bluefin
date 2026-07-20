# e03s01: Add metadata, link, and size-budget validation

## 1. Type

Documentation tooling.

## 2. Risk

P1: validation runs in the commit path.

## 3. Context

Documentation quality currently relies on manual review.

## 4. Problem

Missing metadata, broken links, and oversized skills can regress silently.

## 5. Users

Contributors maintaining agent documentation.

## 6. Value

Common documentation failures are caught before review.

## 7. Scope

Add a standard-library validator and run it through pre-commit.

## 8. Requirements

### ADDED: Documentation validation

The validator checks required skill metadata, index coverage, local links, and
configured size budgets.

## 9. Assumptions

The validator can use Python standard library only.

## 10. Dependencies

Markdown files, skill directories, and pre-commit.

## 11. Constraints

Do not add a third-party runtime dependency.

## 12. Implementation steps

1. Add the validator → verify: `test -x .github/scripts/validate-docs.py`
2. Wire pre-commit → verify: `pre-commit run validate-docs --all-files`
3. Check workflow integration → verify: `grep -RIn 'docs/skills' .github/workflows/skill-drift.yml`

## 13. Verification

Run validator, pre-commit, Justfile checks, and actionlint.

## 14. Acceptance criteria

```gherkin
Scenario: Valid documentation passes
  Given all skills have valid metadata and links
  When validation runs
  Then it exits successfully

Scenario: Broken documentation fails
  Given a skill link points to a missing file
  When validation runs
  Then it exits nonzero and names the source path
```

## 15. Edge cases

External URLs and anchor-only links are not treated as local files.

## 16. Out of scope

Full semantic Markdown rendering or remote URL availability checks.

## 17. Risks

A simplistic parser may miss advanced Markdown syntax; keep checks conservative.

## 18. Rollback

Remove the local hook and validator while preserving documentation content.

## 19. Completion evidence

Validator and all repository hooks pass.

## 20. Status

Complete.
