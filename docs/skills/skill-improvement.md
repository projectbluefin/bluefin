---
name: skill-improvement
description: "The skill-improvement mandate — every agent session must produce a skill file update alongside the work."
metadata:
  type: procedure
---

# Skill Improvement Mandate

Every agent session produces two outputs:

1. **The work** — the PR, fix, or improvement
2. **The learning** — what a future agent should know

Output 1 without Output 2 leaves the factory no smarter. The loop only compounds if agents write back.

## Before You Mark Work Complete

Run this checklist before opening a PR for review or marking an issue done:

- [ ] Did I discover any workaround, non-obvious pattern, or convention?
- [ ] Is there a skill file for the area I worked in?
- [ ] If yes — did I update it?
- [ ] If no — did I create one?
- [ ] Is the skill file committed in **this same PR**? (Not a follow-up. Same PR.)

If all five are checked, you're done. If any are unchecked, finish them first.

---

## What Counts as a Learning Worth Writing Back

**Write it:**

| Category | Example |
|---|---|
| Upstream bug workaround | "GNOME 47 broke this dconf key — use `x-gnome-47/` prefix instead." |
| Non-obvious correctness requirement | "Must edit both the override file AND the dconf lock file — editing only one silently has no effect." |
| Convention not obvious from code | "Renovate automerges digest/patch/minor PRs. Only major bumps need agent review." |
| Trial-and-error discovery | "SHA pinning for internal `projectbluefin/` refs uses a different policy than third-party — read the comment in the workflow file." |
| **Project-internal fact correction** | "No `:latest` tag exists. The only published tags are `:testing` and `:stable`. Source: `execute-release.yml`." |

**Project-internal fact drift is a first-class failure mode.** When an agent writes documentation about image names, tags, workflow outputs, or registry paths and gets it wrong because it used training data instead of reading the source — that is a skill failure. The fix: read the workflow file, update the skill, add verification commands so the next agent can self-check.

**Do NOT write:**

| Category | Example |
|---|---|
| One-off task note | "Use commit message `fix(gnome): revert dconf key` for this PR" |
| Obvious developer knowledge | "Run git status to see changed files" |
| Ephemeral state | "Renovate is currently paused due to config issue #487" |
| Contradiction of another skill | Update the existing skill file — don't add a new conflicting doc |

---

## Where to Write It

Working in `projectbluefin/bluefin` → write to `docs/skills/` in this repo.

Cross-cutting (affects 2+ repos) → local first, then open a propagation issue in `projectbluefin/common` with `kind/improvement` + `area/agent` labels.

Never touch `ublue-os/*`.

## Which Skill File to Update

```
Changed a workflow?        → docs/skills/ci.md
Changed a build script?   → docs/skills/build.md
Changed a package list?   → docs/skills/packages.md
Changed a release step?   → docs/skills/release.md
Changed security/COPR?    → docs/skills/security.md or copr-security.md
Changed LTS behavior?     → docs/skills/lts.md
New domain entirely?      → create docs/skills/<area>.md
```

Use the closest matching existing skill. Only create a new skill when the change introduces a new domain with no existing home.

---

## How to Commit It

The skill update goes in the **same commit or same PR** as the implementation.

```bash
git add .github/workflows/something.yml docs/skills/ci.md
git commit -m "feat(ci): describe the change

Update docs/skills/ci.md with trigger and behavior.

Assisted-by: Claude Sonnet 4.6 via GitHub Copilot
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

The `skill-drift.yml` CI check warns if you forget. Treat the warning as a hard requirement.

---

## See Also

- `docs/skills/` — all skill files for this repo
- [Factory skill-improvement mandate](https://github.com/projectbluefin/common/blob/main/docs/skills/skill-improvement.md) — canonical version in `common`
