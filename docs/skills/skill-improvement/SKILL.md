---
name: skill-improvement
description: Add, refactor, validate, and maintain agent skills without duplicating facts.
metadata:
  audience:
    - contributor
    - maintainer
  source-of-truth:
    - docs/skills/index.md
    - AGENTS.md
---

# Skill improvement

## When to update a skill

Update a skill in the same change when you discover a reusable workaround,
non-obvious invariant, source correction, or durable project convention.

## Procedure

1. Find the closest existing skill.
2. Confirm the fact against source code or authoritative external documentation.
3. Update the existing skill instead of creating a duplicate.
4. Keep `SKILL.md` focused; move long material to `references/`.
5. Add a verification command for the documented behavior.
6. Update `docs/skills/index.md` only when adding or renaming a skill.
7. Run documentation validation and the repository default gate.

## Rules

- Use one canonical source per mutable fact.
- Do not write session notes, personal machine details, or incident diaries.
- Do not claim repository policy is an AAIF or MCP requirement.
- Do not add client-specific or tool-specific instruction duplicates.
- Do not document behavior that was not checked against source.

## Verify

```bash
python3 .github/scripts/validate-docs.py
pre-commit run --all-files
```
