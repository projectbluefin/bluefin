# Bluefin Skill Router

Agent entry point. Load only the skill that matches the task in front of you.

## Task → Skill

| I need to... | Load |
|---|---|
| Build, validate, or test an image change | `docs/skills/build.md` |
| Add, remove, or adjust RPMs, Flatpaks, or Brewfiles | `docs/skills/packages.md` |
| Debug GitHub Actions or understand workflow behavior | `docs/skills/ci.md` |
| Understand image variants, streams, or flavors | `docs/skills/variants.md` |
| Cut a release or promote streams | `docs/skills/release.md` |
| Fix a stuck, conflicted, or wrong-base PR | [`workflow.md` → Fixing stuck PRs](workflow.md#fixing-stuck-prs) |
| Handle Renovate PRs or auto-merge behavior | `docs/skills/renovate.md` |
| Review COPR usage, cosign, or other security-sensitive changes | `docs/skills/security.md` |
| Review or change COPR isolation logic or the enable/disable/install sequence | [`docs/skills/copr-security.md`](docs/skills/copr-security.md) |
| Work on the LTS image or LTS-specific policy | `docs/skills/lts.md` |
| Build or promote installation ISOs | `docs/skills/iso.md` |

## Reference docs

| Topic | File |
|---|---|
| Build model, repo layout, and local dev loop | [`build.md`](build.md) |
| Issue lifecycle, bonedigger, labels, and PR policy | [`workflow.md`](workflow.md) |
| PR gates by change type | [`pr-checklist.md`](pr-checklist.md) |
| CI workflows, triggers, and failure modes | [`ci.md`](ci.md) |

## Scope rules for agent tasks

- **Doc/onboarding tasks** (update AGENTS.md, add skills, onboard): modify only `docs/` and `AGENTS.md`. Do not create `.github/` workflow files unless the task is explicitly CI work.
- **CI tasks** (fix a workflow, add a check): touch only `.github/` and `docs/skills/ci.md`. Do not touch unrelated files.
- **The Justfile and `docs/` are the source of truth.** When memory and code disagree, code wins.
