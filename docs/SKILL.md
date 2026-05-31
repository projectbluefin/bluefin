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
| Handle Renovate PRs or auto-merge behavior | `docs/skills/renovate.md` |
| Review COPR usage, cosign, or other security-sensitive changes | `docs/skills/security.md` |
| Work on the LTS image or LTS-specific policy | `docs/skills/lts.md` |
| Build or promote installation ISOs | `docs/skills/iso.md` |

## Reference docs

| Topic | File |
|---|---|
| Build model, repo layout, and local dev loop | [`build.md`](build.md) |
| Issue lifecycle, bonedigger, labels, and PR policy | [`workflow.md`](workflow.md) |
| PR gates by change type | [`pr-checklist.md`](pr-checklist.md) |
| CI workflows, triggers, and failure modes | [`ci.md`](ci.md) |
