---
name: bluefin-release
description: >-
  Bluefin stable promotion and release flow. Use when changing
  promote-testing-to-main.yml, reasoning about weekly stable cadence, checking
  why a promotion PR did or did not auto-enqueue, or verifying how manual
  workflow_dispatch releases behave.
metadata:
  type: runbook
  context7-sources:
    - /websites/github_en_actions
---

# Bluefin Release Promotion

## When to Use

- Editing `.github/workflows/promote-testing-to-main.yml`
- Changing stable promotion cadence or release timing
- Debugging `auto/promote-testing-to-main`
- Verifying merge-queue behavior for scheduled vs manual releases

## When NOT to Use

- Package or image-content changes → `docs/skills/packages.md`
- Generic CI failures outside promotion flow → `docs/skills/ci.md`
- LTS-specific release work → `docs/skills/lts.md`

## Core Process

1. **Keep the promotion PR flow intact.**
   `testing` updates open or refresh `auto/promote-testing-to-main`; merging that
   PR is the stable release action.
2. **Weekly stable promotion runs Tuesday at 04:00 UTC.**
   This is the automatic stable-cut cadence for bluefin.
3. **Manual dispatch must still support enqueue.**
   Set `use_merge_queue` with an event check so scheduled runs and
   `workflow_dispatch` both enqueue, while ordinary `push` refreshes only update
   the PR body and branch.
4. **Preserve merge-queue semantics on `main`.**
   `main` is queue-protected; promotion automation must enqueue instead of
   calling `gh pr merge --auto`.
5. **Treat `do-not-merge` as a hard stop.**
   Auto-merge must remain blocked when maintainers apply that label.

## Release Flow

```text
push to testing
  → promote-testing-to-main.yml
  → auto/promote-testing-to-main PR updated

Tuesday 04:00 UTC schedule or manual workflow_dispatch
  → promote-testing-to-main.yml
  → same PR re-evaluated
  → merge queue enqueue allowed
  → approvals + checks pass
  → squash merge to main
  → stable release workflow fires
```

## Hard Rules

- `schedule` for bluefin stable promotion is `0 4 * * 2`
- `use_merge_queue` must be true for `schedule` and `workflow_dispatch`
- `use_merge_queue` must stay false for ordinary `push` events
- External `uses:` references stay SHA-pinned; managed internal `projectbluefin/actions`
  reusables stay on their approved `@v1` tag

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Push-triggered promotion should auto-enqueue too." | That makes every testing refresh race straight into the queue. Weekly/manual cadence is intentional. |
| "Manual dispatch is only for debugging." | Maintainers use it for mid-week stable cuts; it must preserve queue behavior. |
| "The cron time is arbitrary." | Tuesday 04:00 UTC is chosen so Europe sees stable by roughly 06:00 CET. |

## Red Flags

- changing `use_merge_queue` back to unconditional `true`
- changing the schedule away from Tuesday 04:00 UTC without a release-plan update
- replacing external SHA pins with floating tags, or replacing managed internal
  `projectbluefin/actions` refs with ad-hoc values
- describing push-triggered PR refreshes as stable releases

## Verification

- [ ] `promote-testing-to-main.yml` schedules Tuesday at `0 4 * * 2`
- [ ] `use_merge_queue` is conditional on `schedule || workflow_dispatch`
- [ ] External refs remain SHA-pinned and internal `projectbluefin/actions` refs
  stay on the approved `@v1` tag
- [ ] Manual dispatch still supports a queued stable release
