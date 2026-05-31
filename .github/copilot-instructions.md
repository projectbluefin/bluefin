# Bluefin — Agent & Copilot Instructions

Bluefin is [`projectbluefin/bluefin`](https://github.com/projectbluefin/bluefin), a Fedora-based rpm-ostree desktop delivered as a bootable OCI image. This repo builds the main GNOME image with a Containerfile plus staged shell scripts, then promotes tested images through the Project Bluefin pipeline. Treat it as an immutable-image repo, not a mutable package-managed workstation.

## Load the right skill first

Read [`docs/SKILL.md`](../docs/SKILL.md) first, then load the skill that matches the task.

| Task | Read |
|---|---|
| Build, validate, or prepare a PR | [`docs/skills/build.md`](../docs/skills/build.md) |
| Add, remove, or adjust RPMs, Flatpaks, or setup hooks | [`docs/skills/packages.md`](../docs/skills/packages.md) |
| Debug GitHub Actions or promotion behavior | [`docs/skills/ci.md`](../docs/skills/ci.md) |
| Understand image variants, streams, or flavors | [`docs/skills/variants.md`](../docs/skills/variants.md) |
| Cut a release or promote streams | [`docs/skills/release.md`](../docs/skills/release.md) |
| Handle Renovate PRs or config | [`docs/skills/renovate.md`](../docs/skills/renovate.md) |
| Review COPR, cosign, or secureboot decisions | [`docs/skills/security.md`](../docs/skills/security.md) |
| Work on the LTS variant repo | [`docs/skills/lts.md`](../docs/skills/lts.md) |
| Build or promote installation ISOs | [`docs/skills/iso.md`](../docs/skills/iso.md) |

## Repo layout

```text
Containerfile                          # Top-level rpm-ostree image definition
Justfile                               # Main operator interface: check, fix, build, changelogs
build_files/
  base/                                # Base image scripts run in numeric order
  dx/                                  # DX layer scripts
  shared/                              # Shared helpers (build.sh, copr-helpers.sh, validation)
system_files/
  shared/                              # Files and hooks copied into all images
  dx/                                  # DX-only overlay files
docs/
  SKILL.md                             # Task router
  workflow.md                          # Issue lifecycle, bonedigger, labels, PR policy
  pr-checklist.md                      # PR gates by change type
  build.md                             # Build model and local dev loop
  ci.md                                # Workflow and promotion reference
  skills/                              # Condensed per-task skill files
.github/
  workflows/                           # PR validation, build, promotion, bonedigger, Renovate automation
  renovate.json5                       # Renovate targeting and package rules
  pull_request_template.md             # PR checklist and author responsibility
```

## Non-negotiable rules

1. **Conventional commits** — every commit and PR title must follow Conventional Commits.
2. **Stay surgical** — make minimal, targeted changes; do not refactor unrelated parts of the repo.
3. **Validate before committing** — run `just check && pre-commit run --all-files`.
4. **No casual local image builds** — only run full builds when testing actual image/container changes; they are expensive.
5. **Attribution is mandatory** — every AI-authored commit must include:
   ```text
   Assisted-by: <Model> via <Tool>
   ```
6. **Copr security is mandatory** — COPR packages must use `copr_install_isolated()` from `build_files/shared/copr-helpers.sh`; never mix Fedora and COPR package arrays.

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

`projectbluefin/common` provides the shared OCI layer. `projectbluefin/testsuite` gates promotion. Bluefin contributors open PRs against `testing`, while the image-promotion workflows still advance published streams from `main` to `latest` and `stable`.

### Issue lifecycle

See [`docs/workflow.md`](../docs/workflow.md) for full detail. The lifecycle is:

```text
filed → approved → queued → claimed → done
```

Meaning:
- `filed`: issue opened; bonedigger preserves triage context
- `approved`: maintainer signed off
- `queued`: ready to claim
- `claimed`: actively being worked
- `done`: fix shipped; verification closes the loop

### Bonedigger data donation contract

Bluefin issue reports are treated as structured data donations.

- `ujust report` captures system state before or while filing an issue.
- `ujust confirm <issue>` records another user hitting the same bug on real hardware.
- `ujust verify <issue>` confirms the shipped fix worked and moves the issue toward closure.

If an issue shows `report: attached`, read the attached gist before proposing a fix. Confirm count is a priority signal. Do not ignore the verification loop without maintainer approval.

### PR comment policy

- One comment per PR event at most; combine findings.
- Never duplicate GitHub UI state such as approvals, checks, or mergeability.
- Test reports should only say what ran, whether it passed, and what is blocked.
- No diff summaries.
- Use `@mentions` only when asking a specific person to do something.
- If there is nothing actionable to add, do not comment.

### Mandatory gates

Non-compliance should be treated as rejection-worthy.

- Base branch: `testing`
- Merge method: squash only
- No WIP PRs
- Max 4 open PRs per agent
- `just check && pre-commit run --all-files`
- Conventional Commits for PR titles and commits
- `Assisted-by: <Model> via <Tool>` on AI-authored commits

For change-specific gates, also read [`docs/pr-checklist.md`](../docs/pr-checklist.md).

## Bluefin philosophy — anti-legacy tenets

Bluefin aggressively moves users away from legacy Linux patterns. This is an architectural constraint, not a preference.

### Flatpak first

GUI applications should default to Flatpak. Do not solve GUI app requests by layering more RPMs unless the image genuinely requires a system dependency.

### No X11 fallbacks

Do not suggest switching to X11, documenting X11 workarounds, or treating X11 as the compatibility path. Prefer Wayland-native apps; otherwise isolate legacy apps in distrobox.

### No `dnf`, `yum`, or mutable-system guidance

This repo builds an immutable image. Do not suggest `dnf install` as the normal operating model for Bluefin users. Prefer:
- Flatpak for GUI apps
- Homebrew or built-in tooling for CLI/dev tools
- distrobox for legacy or mutable workflows

### No PowerShell

Bluefin is a Linux-first environment. Do not introduce PowerShell-based solutions.

### Document the new path, not the workaround

When Bluefin rejects an old Linux pattern, document the modern replacement instead of teaching legacy escape hatches.

### Bury the past

If something only works through old-school Linux desktop tricks, the preferred answer is usually to isolate it in distrobox or replace it with a modern alternative.

## Branch rules

- **All PRs target `testing`. Never `main`.**
- **Squash merge only** for this repo.
- `testing` is the contribution branch; `main` feeds testing-image publication; `latest` and `stable` are promoted branches.
- Renovate must target `testing`. `.github/renovate.json5` should keep:
  ```json5
  "baseBranchPatterns": ["testing"]
  ```
- If CI does not run on a PR, first confirm the PR targets `testing`.

## Related projects

- Documentation: [projectbluefin/bluefin-docs](https://github.com/projectbluefin/bluefin-docs) / [docs.projectbluefin.io](https://docs.projectbluefin.io)
- Shared OCI layer: [projectbluefin/common](https://github.com/projectbluefin/common)
- LTS variant: [projectbluefin/bluefin-lts](https://github.com/projectbluefin/bluefin-lts)
- Installation media: [projectbluefin/bluefin-iso](https://github.com/projectbluefin/bluefin-iso)
