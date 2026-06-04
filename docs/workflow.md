# Bluefin workflow reference

## Repo rules

- Default development branch: `testing`
- All PRs target `testing` — never `main`
- Merge method: squash only
- No WIP PRs
- Max 4 open PRs per agent at a time
- Conventional Commits required on every PR title/commit
- AI-authored commits must include `Assisted-by: <Model> via <Tool>`

## Git workflow for agents

**Always branch from the remote `projectbluefin/testing`, never from local HEAD.** Local `testing` may carry unpushed commits from previous sessions that will silently pollute your PR.

```bash
# Correct way to start any new branch:
git fetch projectbluefin
git checkout -b my-feature projectbluefin/testing
```

**One clean squash commit per PR.** Use `git commit --amend` or `git rebase -i` before pushing to ensure the PR contains exactly one commit.

**Always push to the `projectbluefin` remote**, never `origin` (`origin` points to `ublue-os/bluefin`):

```bash
git push projectbluefin my-feature
```

**Never `git push` or `git push origin`.** Always name the remote explicitly.

## Issue tracker

> **All Bluefin issues go in [`projectbluefin/bluefin`](https://github.com/projectbluefin/bluefin/issues).**
>
> Do **NOT** open, comment on, or modify issues, PRs, or code in any repo outside the `projectbluefin` org — including `ublue-os`, `coreos`, or any other org. Only `projectbluefin/*` repos are in scope.

## Issue flow

`filed → approved → queued → claimed → done`

| Stage | Meaning |
|---|---|
| `filed` | Issue opened; bonedigger adds or preserves triage context |
| `approved` | A maintainer signs off on the work |
| `queued` | Ready for contributors/agents to claim |
| `claimed` | Someone is actively working the issue |
| `done` | Fix shipped; community verification closes the loop |

## Bluefin 🦖 pipeline widget examples

### Filed

```text
Bluefin 🦖  ·  issue pipeline
─────────────────────────────────────────────────
  ▶  filed      report received
  ·  approved   —
  ·  queued     —
  ·  claimed    —
  ·  done       —
─────────────────────────────────────────────────
  report:       attached    ·  confirms: 0
  area:         —           ·  priority: —
  next action:  same bug? ujust confirm 42
```

### Approved + queued

```text
Bluefin 🦖  ·  issue pipeline
─────────────────────────────────────────────────
  ✓  filed      report received
  ✓  approved   signed off by a maintainer
  ▶  queued     waiting for a contributor to claim
  ·  claimed    —
  ·  done       —
─────────────────────────────────────────────────
  report:       attached    ·  confirms: 2
  area:         gnome       ·  priority: high
  next action:  comment /claim to take this
```

### Claimed

```text
Bluefin 🦖  ·  issue pipeline
─────────────────────────────────────────────────
  ✓  filed      report received
  ✓  approved   signed off by a maintainer
  ✓  queued     —
  ▶  claimed    @username
  ·  done       —
─────────────────────────────────────────────────
  report:       attached    ·  confirms: 2
  area:         gnome       ·  priority: high
  next action:  /unclaim to return to queue if stuck
```

### Done

```text
Bluefin 🦖  ·  issue pipeline
─────────────────────────────────────────────────
  ✓  filed      report received
  ✓  approved   signed off by a maintainer
  ✓  queued     —
  ✓  claimed    —
  ▶  done       fix shipped
─────────────────────────────────────────────────
  report:       attached    ·  verified: 1/3
  area:         gnome       ·  priority: high
  next action:  ujust verify 42 — three verifies closes the case
```

## Agent label checklist — when opening a PR

When an agent opens a PR that fixes an issue, update labels on both the issue and the PR:

**On the linked issue:**
1. Remove `queue/agent-ready`
2. Add `queue/claimed`

**On the PR:**
1. Add `queue/claimed` — signals the work is done and a human is next to review

These steps mark the transition from "available for an agent to pick up" to "awaiting human review". Not applying them leaves the issue appearing unclaimed in the queue and gives reviewers no signal that the PR is ready.

## Bonedigger commands

| Command | Who uses it | Effect |
|---|---|---|
| `/claim` | contributors/agents | Assign the issue and move it into the claimed state |
| `/unclaim` | claimant or maintainer | Drop assignment and return it to the queue |
| `/approve` | maintainer | Mark approved and queue it for work |
| `/lgtm` | maintainer | Alias for `/approve` |
| `/wontfix [reason]` | maintainer | Close as not planned with a reason |

Bonedigger is wired in via `.github/workflows/bonedigger.yml` and uses the reusable lifecycle workflow from `projectbluefin/bonedigger` with Bluefin branding (`Bluefin`, `🦖`).

## Labels

### Lifecycle labels

These are the labels bonedigger expects and/or manages for the issue queue:

- `needs-triage`
- `status/discussing`
- `status/approved`
- `queue/agent-ready`
- `queue/claimed`
- `priority/high`
- `priority/critical`
- `lgtm`
- `stale`

### Hive tracking labels

These labels are managed by Hive agents and humans triaging from the live Hive snapshot. They are **dynamic** — reset each cycle — and distinct from the static `priority/` labels.

| Label | Color | When to apply |
|---|---|---|
| `hive/p0` | 🔴 `#d93f0b` | Active cycle release blocker — must land before next promotion |
| `hive/p1` | 🟠 `#e4a117` | Active cycle high priority — should land this cycle |

**Coexistence with bonedigger labels:** `hive/p0` and `hive/p1` coexist with `priority/high` and `priority/critical`. They serve different purposes: `priority/*` is the repo's static backlog priority; `hive/*` means the Hive formation is actively tracking this issue right now.

To find all current Hive blockers across the org:
```bash
gh search issues --label "hive/p0" --owner projectbluefin --state open
gh search issues --label "hive/p1" --owner projectbluefin --state open
```

### Common Bluefin labels already in use

- Kind: `kind/bug`, `kind/documentation`, `kind/enhancement`, `kind/github-action`, `kind/question`, `kind/renovate`, `kind/tech-debt`, `kind/wontfix`, `kind/duplicate`, `kind/parity`
- Area: `area/brew`, `area/flatpak`, `area/iso`, `area/just`, `area/testing`, `area/gnome`, `area/nvidia`, `area/hardware`, `area/policy`, `area/services`, `area/upstream`, `area/finpilot`, `area/bluespeed`, `area/aurora`, `area/buildstream`, `area/bling`
- Other useful labels: `dependencies`, `release-blocker`, `package-requests`, `good first issue`, `help wanted`, `agent-ready`

## Fixing stuck PRs

### PR targets wrong base branch

If a PR targets `main` instead of `testing`, `pr-validation.yml` will never run (it only triggers on PRs to `testing`), and the merge queue ruleset on `main` will block the enqueue because the `validate` check has not passed.

Fix: retarget the PR.

```bash
gh pr edit <number> --repo projectbluefin/bluefin --base testing
```

### PR is BEHIND (branch out of date)

`mergeStateStatus: BEHIND` means the PR branch has diverged from `testing`. Auto-merge will not fire and the branch cannot be enqueued until it is updated.

If the branch has only relevant commits, rebase it:
```bash
git fetch projectbluefin testing
git checkout <branch>
git rebase projectbluefin/testing
git push projectbluefin <branch> --force
```

If the branch has accumulated **unrelated commits** on top of the intended fix, cherry-pick only the relevant commit onto a clean branch:
```bash
git checkout projectbluefin/testing -b <branch>-clean
git cherry-pick <commit-sha>
just check
git push projectbluefin <branch>-clean:<branch> --force   # updates the open PR
gh pr merge <number> --repo projectbluefin/bluefin --squash
git push projectbluefin --delete <branch>-clean            # clean up temp branch
```

### PR is DIRTY (merge conflicts)

Same fix as BEHIND — rebase or cherry-pick onto the latest `testing`.

For Renovate/chore PRs with conflicts, trigger a central Renovate run to rebase them automatically:
```bash
gh workflow run "Renovate Self-Hosted" --repo projectbluefin/renovate-config
```

### Auto-merge cannot be enabled

`testing` has no branch protection. GitHub requires branch protection to enable auto-merge, so `gh pr merge --auto` will fail with "Protected branch rules not configured."

Just squash-merge directly instead:
```bash
gh pr merge <number> --repo projectbluefin/bluefin --squash
```

For a batch of chore/Renovate PRs:
```bash
for pr in 101 102 103; do
  echo -n "PR #$pr: "
  gh pr merge $pr --repo projectbluefin/bluefin --squash 2>&1
done
```

PRs that show merge conflicts will need the Renovate rebase trigger above first.

## PR comment policy

- One comment per PR event at most; combine findings
- Do not duplicate GitHub UI state (approvals, check runs, mergeability)
- Test reports should only say what ran, whether it passed, and what is blocked
- Use `@mentions` only when asking a specific person to do something
- If there is nothing actionable to add, do not comment

## Links

- [bonedigger README](https://github.com/projectbluefin/bonedigger)
- [Bluefin pull request template](../.github/pull_request_template.md)
