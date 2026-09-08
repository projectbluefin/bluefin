---
name: dependency-automation
version: "1.2"
last_updated: 2026-08-16
id: dependency-automation
one_line_purpose: Review Renovate configuration and automated dependency updates.
entry_point: docs/skills/dependency-automation/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [renovate, dependencies, automation, automerge]
description: >-
  Describes the Renovate configuration, automerge workflow, and
  authentication model for automated updates. Use when changing dependency
  automation config or triaging an automated update pull request.
metadata:
  type: procedure
  source-of-truth:
    - .github/renovate.json5
    - .github/workflows/renovate-automerge.yml
---

# Dependency automation

## Procedure

1. Read the canonical `.github/renovate.json5` configuration and the affected
   workflow. Do not add another supported Renovate config filename: Renovate
   stops at the first match and would silently shadow the canonical file.
2. Validate configuration changes with the repository's configured validator.
3. Preserve the configured authentication model: pass the MergeRaptor App
   credentials to the reusable auto-merge workflow. A merge performed with
   `GITHUB_TOKEN` suppresses the resulting `push` workflow, so testing images
   would not build. Never add personal access tokens or user credentials.
4. Confirm the pull request targets the development branch.
5. Run the default gate.

```bash
just check
pre-commit run --all-files
```

Do not document an automation rule until it is present in source configuration.

## When to Use

Use for Renovate or dependency-automation behavior.

## When NOT to Use

Do not use for Manual package changes that automation does not own.

## Core Process

Read configuration, validate it, and preserve the configured auth model.

## Common Rationalizations

- "A shortcut is harmless." Follow the source-of-truth and verification rules instead.

## Red Flags

- Adding tokens or documenting rules absent from source.

## Verification

- [ ] The selected source and focused command were checked.
- [ ] The repository default gate passes.
