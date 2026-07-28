# e03s02: Publish and enforce the skill-improvement procedure

## 1. Type

Documentation governance.

## 2. Risk

P2: process guidance only.

## 3. Context

Reusable discoveries need a canonical place to prevent repeated mistakes.

## 4. Problem

Without a write-back rule, agent knowledge decays or becomes session-specific.

## 5. Users

Agents and maintainers adding or refactoring skills.

## 6. Value

The skill catalog improves alongside implementation changes.

## 7. Scope

Publish the meta-skill with ownership, source validation, and review triggers.

## 8. Requirements

### ADDED: Skill improvement procedure

Reusable facts must be source-validated, written to the closest skill, and
verified in the same change.

## 9. Assumptions

Skills remain repository Markdown rather than a proprietary service.

## 10. Dependencies

`AGENTS.md`, the skill index, and the documentation validator.

## 11. Constraints

No session diaries, personal infrastructure, or duplicated policy.

## 12. Implementation steps

1. Publish the meta-skill → verify: `test -f docs/skills/skill-improvement/SKILL.md`
2. Add canonical-fact rules → verify: `grep -q canonical docs/skills/skill-improvement/SKILL.md`
3. Add review guidance → verify: `grep -q review docs/skills/skill-improvement/SKILL.md`

## 13. Verification

Run documentation validation and the default repository gate.

## 14. Acceptance criteria

```gherkin
Scenario: Reusable learning is written back
  Given an agent discovers a durable repository invariant
  When the change is completed
  Then the closest skill contains the invariant and its verification command

Scenario: Ephemeral notes are rejected
  Given a proposed skill update contains session-only details
  When it is reviewed
  Then those details are removed
```

## 15. Edge cases

A new domain may create a skill only when no existing skill is appropriate.

## 16. Out of scope

Automatic extraction of learnings from chat transcripts.

## 17. Risks

Over-documenting transient facts increases drift; source links and budgets limit it.

## 18. Rollback

Restore the prior skill-improvement document.

## 19. Completion evidence

The meta-skill is indexed, validated, and source-linked.

## 20. Status

Complete.
