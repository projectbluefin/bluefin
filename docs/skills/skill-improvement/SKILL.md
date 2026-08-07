---
name: skill-improvement
version: "1.0"
last_updated: 2026-08-06
id: skill-improvement
one_line_purpose: Maintain and refactor agent skills without duplicating facts.
entry_point: docs/skills/skill-improvement/SKILL.md
category: meta
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [skills, documentation, maintenance, agents]
description: >-
  Explains when to update an existing skill, how to avoid duplicating
  source-of-truth facts, and how to split oversized skills. Use when a
  reusable fact or procedure changes and a skill must follow.
metadata:
  type: procedure
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
- Cross-repo procedure is canonical in `projectbluefin/common`; link it rather
  than copying it into this repository.
- Do not write session notes, personal machine details, or incident diaries.
- Do not claim repository policy is an AAIF or MCP requirement.
- Do not add client-specific or tool-specific instruction duplicates.
- Do not document behavior that was not checked against source.
- Do not add a bespoke per-convention CI gate to enforce skill discipline. The
  factory retired `skill-drift` for that reason; see
  [`common/docs/skills/skill-drift.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/skill-drift.md).
  The mandate is enforced at developer time by `pre-commit` and at review.

## Where a learning goes

Working in this repository, write to the closest `docs/skills/<name>/SKILL.md`.
When the learning affects two or more factory repositories, apply it locally,
then file an issue in `projectbluefin/common` describing the propagation. Do not
self-apply a queue label. Never write to `ublue-os/*`. The canonical mandate is
[`common/docs/skills/skill-improvement.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/skill-improvement.md).

## Every-loop repair contract

Run this on every task, including tasks that succeed:

1. Verify the repository, branch, and loaded skills against source.
2. Name stale guidance explicitly instead of silently working around it.
3. Repair the nearest authoritative skill when the correction is source-backed
   and in scope.
4. Validate with the checks that already exist; do not invent a new gate.
5. Record the learning and any unresolved gap.
6. Escalate a human gate rather than turning uncertainty into policy.

A successful task still checks for reusable learning and documentation drift
before completion.

## Verify

```bash
python3 .github/scripts/validate-docs.py
pre-commit run --all-files
```

## When to Use

Use for Adding or refactoring a reusable agent skill.

## When NOT to Use

Do not use for Ephemeral session notes or unrelated implementation.

## Core Process

Source-check the fact, update the closest skill, add verification, run documentation gates.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Creating duplicate skills or recording transient incident state.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
