---
name: skill-improvement
version: "1.1"
last_updated: 2026-08-07
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
  Applies the factory skill-update mandate to this repository: which skill to
  edit, what not to duplicate, and how to validate. Use when a reusable fact or
  procedure changes and a skill must follow.
metadata:
  type: procedure
  audience:
    - contributor
    - maintainer
  source-of-truth:
    - .github/scripts/validate-docs.py
    - docs/skills/index.md
    - AGENTS.md
---

# Skill improvement

## When to Use

- You discovered a reusable workaround, non-obvious invariant, source
  correction, or durable project convention while doing other work.
- A source file changed and an existing skill now describes it incorrectly.

## Do not use when

- Creating a brand-new skill directory: use
  [write-a-skill](../write-a-skill/SKILL.md).

## Canonical mandate

The obligation to repair skills, and its rationale, are canonical in
[`common/docs/skills/skill-improvement.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/skill-improvement.md).
Read it there; do not restate it here.

The factory deliberately has **no** bespoke per-convention CI gate enforcing
skill discipline — `skill-drift` was retired, and
[`common/docs/skills/skill-drift.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/skill-drift.md)
records why. Enforcement is developer-time (`pre-commit`) plus review. Do not
add a replacement gate.

## Procedure

1. Find the closest existing skill in [`index.md`](../index.md).
2. Confirm the fact against source code, a workflow file, or authoritative
   external documentation. Never document unverified behavior.
3. Update that skill rather than creating a near-duplicate.
4. Keep `SKILL.md` under the enforced 180-line cap; move long material to
   `docs/skills/<name>/references/`.
5. Add or update a `## Verification` command that re-derives the documented
   fact.
6. Bump `version` and set `last_updated` when the content materially changes.
7. Touch `index.md` only when adding, renaming, retiring, or repurposing a
   skill — its row text should match the skill's `one_line_purpose`.
8. Run the gates.

## Where a learning goes

Working in this repository, write to the closest
`docs/skills/<name>/SKILL.md`. When the learning affects two or more factory
repositories, apply it locally, then file an issue in `projectbluefin/common`
describing the propagation. Do not self-apply a queue label. Never write to
`ublue-os/*`.

## Rules

- One canonical source per mutable fact.
- Cross-repo procedure is canonical in `projectbluefin/common`; link it rather
  than copying it into this repository.
- Do not write session notes, personal machine details, or incident diaries.
- Do not claim repository policy is an AAIF or MCP requirement.
- Do not add client-specific or tool-specific instruction duplicates.

## Red Flags

- Creating a second skill for a domain an existing skill already owns.
- Recording transient incident state or a session narrative.
- Copying text out of `projectbluefin/common` instead of linking it.
- Editing a skill without bumping `version` / `last_updated`.
- Proposing a new CI check to police documentation conventions.

## Verification

- [ ] `python3 .github/scripts/validate-docs.py` prints its `documentation ok`
      line with no errors.
- [ ] `pre-commit run validate-docs --all-files` passes.
- [ ] `git diff --name-only` shows the skill and its source change together.
