---
name: skill-improvement
description: Add, refactor, validate, and maintain repository skills without duplicating facts.
metadata:
  source-of-truth:
    - AGENTS.md
    - docs/skills/index.md
    - .github/scripts/validate-docs.py
---

# Skill improvement

## When to Use

Use when a change reveals a reusable procedure or invariant, an existing skill
is stale or too broad, or a new task capability has no suitable skill.

## When NOT to Use

Do not use for session notes, temporary incidents, personal machine details, or
unrelated implementation changes.

## Core Process

1. Identify the closest existing skill.
2. Confirm the fact against source or an authoritative external document.
3. Update the existing skill instead of creating a duplicate.
4. Keep `SKILL.md` focused; move deep material to `references/`.
5. Add or update a verification command.
6. Update `docs/skills/index.md` only when adding or renaming a skill.
7. Run documentation validation and relevant repository checks.

## Rules

- Use one canonical source per mutable fact.
- Do not claim repository policy is an AAIF or MCP requirement.
- Do not create client-specific or tool-specific instruction duplicates.
- Do not document behavior that was not checked against source.

## Common Rationalizations

- “The fact is obvious.” Verify it and record it once at the canonical location.
- “A new skill is simpler.” Reuse the closest skill unless the task boundary is genuinely different.
- “I will update the skill later.” Write back durable discoveries in the same change.

## Red Flags

- Duplicate commands or policy in multiple skills.
- A skill contains session history or unresolved work.
- A source-of-truth path or verification command is missing.
- The index points to a missing or renamed skill.

## Verification

```bash
python3 .github/scripts/validate-docs.py
pre-commit run --all-files
```

- [ ] Source and focused command were checked.
- [ ] The skill is indexed and within its size budget.
- [ ] No transient or client-specific content was added.
