# CI failure triage

| Symptom | First check |
|---|---|
| No checks | Pull request base branch and path filters |
| Validation differs locally | Run `just check` and `pre-commit run --all-files` |
| Workflow did not trigger | Event, branch, and path filters in the YAML |
| Promotion is blocked | Exact digest, required check, and merge-group state |
| Shared action behaves incorrectly | Reusable workflow source and its callers |

Always inspect the failed run logs before changing a workflow.

## Reading a failed `post-testing-e2e` run

`promote-to-testing` in `.github/workflows/post-testing-e2e.yml` needs
`run-e2e.result == 'success'`, so a single failing matrix leg makes the whole
gate `skipped`. Identify the failing leg and its failing scenarios before
concluding anything about the image:

```bash
gh run view RUN_ID --repo projectbluefin/bluefin --json jobs \
  --jq '.jobs[] | [.name, .conclusion] | @tsv'
gh run view RUN_ID --repo projectbluefin/bluefin --log \
  | grep -A20 'Failing scenarios:'
```

The behave summary line (`N scenarios passed, N failed`) and the
`Failing scenarios:` block name the exact feature file and line. That is the
only evidence that identifies the failure; job names do not.

## The `oras` screenshot error is not the failure

In `projectbluefin/testsuite`'s `e2e.yml@v1`, the `Push desktop screenshot to
GHCR` step builds a tag with
`IMAGE_SLUG=$(echo "${IMAGE}" | sed 's|ghcr.io/[^/]*/||' | tr ':' '-')`.
When the caller passes a digest reference — `post-testing-e2e.yml` passes
`ghcr.io/<owner>/bluefin@sha256:…` — the slug keeps the `@sha256-…` suffix and
`oras push` rejects it:

```
invalid reference: invalid digest "sha256-…"
```

That step is `continue-on-error: true`, so it produces a red `##[error]` line in
the log without failing the job. Runs that pass `:testing` by tag (for example
`nightly.yml`) do not show it at all. Do not report it as the cause of a
`post-testing-e2e` failure; find the behave summary instead.

## `:testing` promotion blocker set (issue #989) — re-verified 2026-08-10

`run-e2e / smoke,common / GNOME 50 — smoke-a` has failed on essentially every
`post-testing-e2e` run since 2026-06-25, making `promote-to-testing` `skipped`
(it needs `run-e2e.result == 'success'`). The root cause and fix are **owned by
`projectbluefin/testsuite`**, not this repo — bluefin ships Firefox as an
unmodified RPM and no bluefin-side change correlates with the regression
window. Do not attempt to work around this from `bluefin` by adding
`always()`, `continue-on-error`, or dropping `run-e2e` from
`promote-to-testing`'s `needs:` — that would promote an unverified digest.

State as of run
[31358323820](https://github.com/projectbluefin/bluefin/actions/runs/31358323820)
(2026-08-10T05:21Z):

- All six `firefox.feature` scenarios still fail deterministically, through
  both `@retry` passes, with `AssertionError: Firefox address bar not found`
  (and the matching tab-list / "still visible" assertions for the Ctrl+T /
  Ctrl+W / Ctrl+Q scenarios).
- `testsuite#692` (merged 2026-08-07, in the current `v1` tag) fixed the
  original bug: Firefox launched without `GNOME_ACCESSIBILITY=1`, so its
  AT-SPI subtree never populated, and `_firefox_window()` falsely accepted a
  bare `filler` node as a healthy window. That fix is real but **incomplete**:
  the "main window is accessible" step now passes because the window exposes
  *some* populated chrome (for example a toolbar or push button), but the
  address-bar `entry` node specifically still never appears, so
  `_address_bar()` still raises.
- `testsuite#741` (open as of this writing, refs this issue) targets a
  further gap: an exported Flatpak `.desktop` launch path does not carry
  `FIREFOX_A11Y_ENV` across the sandbox boundary, which reproduces the same
  address-bar/tab-list symptom. Re-check whether `#741` (or a follow-up) is
  merged and the testsuite `v1` tag has advanced past it before re-triaging
  this from scratch — `run-testsuite.yml` always resolves `test_ref: v1`, so a
  merged fix does not reach `bluefin` until that tag moves.
- Unblock criterion: one green `Post-Testing E2E` run with
  `promote-to-testing: success` after the testsuite fix lands closes this
  issue. There is nothing to change in `bluefin` itself beyond re-verifying
  that run.
