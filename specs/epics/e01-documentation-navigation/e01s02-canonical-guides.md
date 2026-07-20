# e01s02: Consolidate canonical supporting documentation

## 1. Type

Documentation refactor.

## 2. Risk

P2: links and guidance move without runtime behavior changes.

## 3. Context

Build, contribution, QA, release, and workflow facts are duplicated.

## 4. Problem

Agents cannot identify the canonical home for a mutable fact.

## 5. Users

Contributors, maintainers, evaluators, and coding agents.

## 6. Value

Each stable topic has one compact source-linked document.

## 7. Scope

Add canonical documents and retain short compatibility pointers.

## 8. Requirements

### ADDED: Canonical supporting guides

Architecture, contribution, QA, release, and workflow topics each have one
canonical document with source-of-truth guidance.

## 9. Assumptions

Root README, contribution, and security files remain discoverable entry points.

## 10. Dependencies

Current `Justfile`, `Containerfile`, tests, and workflows.

## 11. Constraints

Do not duplicate complete procedures across root and `docs/` files.

## 12. Implementation steps

1. Add canonical guides → verify: `for f in docs/architecture.md docs/contributing.md docs/qa.md docs/release.md docs/workflow.md; do test -f "$f"; done`
2. Add compatibility pointers → verify: `python3 .github/scripts/validate-docs.py`

## 13. Verification

Run local links, pre-commit, and Justfile checks.

## 14. Acceptance criteria

```gherkin
Scenario: Contributor finds validation guidance
  Given a contributor opens CONTRIBUTING.md
  When they follow the canonical documentation link
  Then they reach the contribution and QA procedures

Scenario: Old documentation links remain safe
  Given a compatibility path is referenced
  When the link is opened
  Then it points to the canonical document
```

## 15. Edge cases

A renamed workflow or command must be checked against source before publication.

## 16. Out of scope

Rewriting externally hosted end-user documentation.

## 17. Risks

A pointer may hide a missing topic; validator and manual review catch this.

## 18. Rollback

Restore the prior supporting documents and links.

## 19. Completion evidence

All canonical files exist and local links validate.

## 20. Status

Complete.
