---
name: write-a-skill
version: "1.1"
last_updated: 2026-08-07
id: write-a-skill
one_line_purpose: Author a new skill directory that satisfies this repository's front-matter contract.
entry_point: docs/skills/write-a-skill/SKILL.md
category: meta
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: [skill-improvement]
tags: [skills, authoring, documentation, front-matter, validation]
description: >-
  Defines the required SKILL.md front-matter keys, size budget, index entry,
  and validation command for a new skill in this repository. Use when adding a
  new docs/skills directory or repairing front matter that fails validation.
metadata:
  type: procedure
  source-of-truth:
    - .github/scripts/validate-docs.py
    - docs/skills/index.md
    - AGENTS.md
---

# Write a skill

## When to Use

- Adding a new `docs/skills/<name>/SKILL.md`.
- Repairing front matter that `validate-docs.py` rejects.

## Do not use when

- Updating an existing skill's body: use
  [skill-improvement](../skill-improvement/SKILL.md).

## Required front matter

Every `docs/skills/<name>/SKILL.md` starts with exactly these keys:

```yaml
---
name: <kebab-case-name>          # must equal the directory name
version: "1.0"                   # quoted semver string
last_updated: YYYY-MM-DD
id: <kebab-case-name>            # must equal name and the directory name
one_line_purpose: <=120 chars, imperative, no "Use when" clause
entry_point: docs/skills/<name>/SKILL.md
category: ci-ops | test-authoring | meta
mcp_compliance_level: partial
optimization_status: draft
status: active | deprecated | reserved
dependencies: []                 # ids of skills that must load first
tags: [tag1, tag2, tag3]         # 3-6 lowercase keywords
description: >-                   # <=256 chars: capability sentence, then
  <capability>. Use when <triggers>.
metadata:
  type: procedure | reference | runbook | policy
  source-of-truth:
    - <path that owns the mutable facts>
---
```

`metadata.source-of-truth` is load-bearing: it tells an agent which files to
read before documenting mutable behavior. Never drop it when editing front
matter. `metadata` accepts additional keys (`audience`, `context7-sources`).

## Procedure

1. Confirm no existing skill covers the domain. Prefer updating one.
2. Create `docs/skills/<name>/SKILL.md` with the front matter above.
3. Write real values. `one_line_purpose` and `description` must describe this
   skill specifically; templated filler is a defect.
4. Add a row to [`index.md`](../index.md) linking `<name>/SKILL.md`.
5. Move long detail to `docs/skills/<name>/references/*.md` and link it.
6. Run the validation gate.

## Body sections

1. `## When to Use` — concrete triggers.
2. `## Do not use when` — pointers to the neighbouring skills.
3. `## Procedure` or `## Decision tree` — the agent workflow.
4. `## Red Flags` — the failure signatures a reader should recognise.
5. `## Verification` — exact commands that re-derive project-internal facts.

`validate-docs.py` does not check headings, so this ordering is a convention;
keep it consistent so agents can skim any skill the same way.

## Local variances from projectbluefin/common

This repository intentionally diverges from `projectbluefin/common`:

- **Per-skill directories only.** Every skill is
  `docs/skills/<name>/SKILL.md`. Flat `docs/skills/<name>.md` files are not
  recognized by `validate-docs.py` and will fail the missing-`SKILL.md` check.
- **Hard 180-line cap** per `SKILL.md`, enforced by `validate-docs.py`, rather
  than common's 200-line soft / 500-line hard budget. `AGENTS.md` is capped at
  150 lines and `docs/skills/index.md` at 80.
- **Hand-curated index.** This repository does not adopt common's generated
  `index.json`, `index.schema.json`, or `generate_skill_index.py`. The catalog
  is small enough to curate by hand; `validate-docs.py` fails if a skill is
  missing from `index.md`.
- **No external YAML dependency.** `validate-docs.py` parses front matter with
  a small hand-rolled reader, so the `validate` CI job needs no extra
  packages. Keep new front-matter constructs simple: top-level scalars, inline
  `[a, b]` lists, folded `>-` blocks, and one nested `metadata` mapping.

## Red Flags

- `id`, `name`, or `entry_point` disagreeing with the directory name.
- A `description` over 256 characters or missing its `Use when` sentence.
- A new skill absent from `index.md`.
- Duplicating a fact that a `source-of-truth` file already owns.
- Templated filler such as a generic "a shortcut is harmless" rationalization.

## Verification

```bash
python3 .github/scripts/validate-docs.py
wc -l docs/skills/*/SKILL.md
pre-commit run --all-files
```
