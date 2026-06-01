# AGENTS.md

Bluefin is [`projectbluefin/bluefin`](https://github.com/projectbluefin/bluefin): a Containerfile-driven rpm-ostree GNOME desktop image.

**Read [`docs/SKILL.md`](docs/SKILL.md) before doing any work.** Load only the docs that match the task.

## Docs router

- [`docs/SKILL.md`](docs/SKILL.md) — task router
- [`docs/workflow.md`](docs/workflow.md) — issue lifecycle, bonedigger, labels, PR policy
- [`docs/pr-checklist.md`](docs/pr-checklist.md) — PR gates by change type
- [`docs/build.md`](docs/build.md) — build model and local validation loop
- [`docs/ci.md`](docs/ci.md) — CI, promotion, and failure modes

## Org pipeline — projectbluefin

### Repo map

```text
common ──────────────────────────┐
(shared OCI layer)               │
                                 ▼
bluefin  (main→stable)       ←── images ──→ testsuite (e2e gate)
bluefin-lts (main→lts)       ←── images ──→ testsuite (e2e gate)
dakota  (main→:latest)       ←── images ──→ testsuite (e2e gate)
                                 │
                                 ▼
                                iso (installation media)
```

Each image repo consumes `projectbluefin/common`. `projectbluefin/testsuite` gates promotion.

## Repo rules

- All PRs target `testing`. Never `main`.
- Merge method: **squash only**.
- No WIP PRs.
- Max 4 open PRs per agent.

## Data donation

Bluefin bugs are data donations.

- `ujust report` captures system state before the issue opens.
- `ujust confirm <issue>` records another real-world hit.
- `ujust verify <issue>` confirms the shipped fix and closes the loop.

**Agent rule:** if an issue says `report: attached`, read the gist first. Treat confirm count as a priority signal. Do not bypass the verification loop without maintainer sign-off. Full details live in [`docs/workflow.md`](docs/workflow.md).

## Mandatory gates

Non-compliance = rejection.

- Read [`docs/SKILL.md`](docs/SKILL.md) before modifying anything.
- Run `just check && pre-commit run --all-files` before every commit.
- Use Conventional Commits for every commit and PR title.
- Every AI-authored commit must include `Assisted-by: <Model> via <Tool>`.
- Keep open PR count at 4 or fewer.
- Do not open WIP PRs.
- **NEVER interact with repos outside the [`projectbluefin`](https://github.com/projectbluefin) org.** Do not open, comment on, or modify issues, PRs, or code in `ublue-os`, `coreos`, or any other org. Only `projectbluefin/*` repos are in scope.

## PR comment policy

- One comment per PR event, max; combine findings.
- Do not duplicate GitHub UI state.
- Test reports: what ran, pass/fail, blockers only.
- No diff summaries.
- `@mentions` only when asking for a specific action.
- If nothing actionable needs saying, post nothing.
