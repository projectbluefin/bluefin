# CI failure triage

| Symptom | First check |
|---|---|
| No checks | Pull request base branch and path filters |
| Validation differs locally | Run `just check` and `pre-commit run --all-files` |
| Workflow did not trigger | Event, branch, and path filters in the YAML |
| Promotion is blocked | Exact digest, required check, and merge-group state |
| Shared action behaves incorrectly | Reusable workflow source and its callers |
| Tests update but E2E setup stays stale | Compare the reusable workflow `uses` ref with its test checkout ref |

Always inspect the failed run logs before changing a workflow.

## A reusable testsuite workflow has two independent refs

`uses` selects the workflow definition; `test_ref` selects the test tree that
workflow checks out. They move separately, so a managed `test_ref` is not
evidence that workflow-level fixes — VM disk sizing, runner setup, anything in
the workflow body — are current. Those arrive only when `uses` moves.

This is a stable-promotion trap: `test_ref: v1` reads as "tests are current"
and says nothing about the workflow running them. Keep both layers on the
documented managed ref, and verify the nested workflow shown in the run log
rather than the ref written in the caller.

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

## Stable promotion blocker set (issue #929) — re-verified 2026-08-10

`Execute Release` has failed on every attempt since July 20 (tracked in #929).
The failing legs move over time; re-check the current run rather than trusting
an older triage comment. State as of run
[31355954836](https://github.com/projectbluefin/bluefin/actions/runs/31355954836)
(2026-08-10T04:35Z, candidate `bluefin:testing` ->
`sha256:bf615b200faefc44b50232ecc8a3eb21490e88dd9316b528b27f54472122611d`):

| Leg | Status | Notes |
|---|---|---|
| `bluefin` / `smoke-a` | failing | Dash to Dock / Firefox / AT-SPI session lookups fail (`gdbus ... Extensions.GetExtensionInfo` returns `UnknownMethod`, Firefox/Settings not found via AT-SPI). No open PR claims this; see prior findings on #929. |
| `bluefin` / `common-b` | failing (new) | `ujust toggle-updates` non-interactive scenario — see below. |
| `bluefin-nvidia` / `common-b` | failing (new) | Same `ujust toggle-updates` failure, identical error, on the NVIDIA variant. |
| `bluefin` / `bluefin-nvidia` smoke-b, common-a | passing | The composefs `cap_net_raw` regression tracked in `testsuite#524` / `dakota#841` **no longer appears** in this run — treat that blocker as resolved unless a fresh run shows it again. |

### New: `ujust toggle-updates` fails with a `gum` TTY error, not a skip

`tests/common/features/common_ujust.feature:30` (`projectbluefin/testsuite`)
exercises `projectbluefin/common`'s non-interactive `toggle-updates ACTION=`
contract (shipped in `common#966`, 2026-08-09). The `@requires_toggle_action`
gate in `tests/common/features/environment.py` probes with
`ujust toggle-updates cancel` and only runs the scenario when that exits `0` —
so the scenario ran here, meaning the probe found ACTION support present, but
the actual `enable`/`disable` exchange still failed:

```
ASSERT FAILED: SSH command exited 1, expected 0
stderr: unable to pick selection: could not open a new TTY: open /dev/tty: no such device or address
```

That message comes only from `gum choose` in the recipe's `*` (unmatched
`ACTION`) branch — the `enable`/`disable`/`cancel` branches never call `gum`.
Reproducing `common@main`'s current `update.just` locally with plain `just`
(1.58.0) resolves `enable`/`disable`/`cancel` correctly with no `gum`
invocation, so the recipe logic on `common@main` is not the bug by itself.
Two explanations remain open, and neither could be checked here — this
runtime has no podman/skopeo/container toolchain to inspect the actual layered
image or reach the ephemeral test VM:

1. The specific `bluefin`/`bluefin-nvidia` image digest above was built
   against a `common` base layer resolved before `common#966` propagated, so
   it still runs the old body (this predicts both variants failing
   identically, which matches).
2. Something in the SSH/session harness (not the recipe) causes `gum` to be
   invoked regardless of `ACTION` in this environment specifically.

Next step: confirm which `common` digest is actually layered into the
`bluefin:testing` image tested above (e.g. via `skopeo inspect` /
`rpm-ostree status` on a real or lab VM, not just the source repo), and if it
already includes `common#966`, escalate as a `projectbluefin/common` or
`projectbluefin/testsuite` bug rather than assuming a stale layer will
self-resolve on the next build.
## `:testing` can silently freeze for weeks, invalidating every downstream triage (#929)

`build-image-testing.yml` never moves the mutable `:testing` tag itself
(`publish_stream_tag: "false"`); only `promote-to-testing` in
`post-testing-e2e.yml` does, and only when every `run-e2e` matrix leg passes.
If one leg (for example `smoke-a`) fails on every run, `promote-to-testing`
is `skipped` every time and `:testing` stops advancing — silently, with no
failed check on the tag itself, because the workflow that would have moved
it never runs the promotion job at all.

This means `Execute Release`'s `gh api .../manifests/testing` lookup can
resolve to a build that is *days or weeks* old relative to `main`/`testing`
HEAD, even though intervening fixes merged and built successfully as
version-alias tags. Triaging a stable-promotion failure by only reading the
latest `Execute Release` log reproduces the same symptoms release after
release and looks like the fixes "didn't work," when the real problem is
that the tested image predates them. Confirm the actual age of the image
under test before attributing a release-gate failure to a specific fix:

```bash
# What Execute Release actually tested (image ref appears in the job env / log)
gh run view RUN_ID --repo projectbluefin/bluefin --log | grep 'IMAGE:'

# Resolve current :testing to its digest and check when that build ran
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:projectbluefin/bluefin:pull" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")
curl -sI -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://ghcr.io/v2/projectbluefin/bluefin/manifests/testing" \
  | grep -i docker-content-digest

# Confirm promote-to-testing's real status, not just the workflow conclusion —
# a failing leg elsewhere still shows the workflow as "failure" while masking
# that the promotion job specifically never even attempted to run
gh run view RUN_ID --repo projectbluefin/bluefin --json jobs \
  --jq '.jobs[] | select(.name=="promote-to-testing") | .conclusion'
```

If `promote-to-testing` has been `skipped` across many consecutive runs, the
single failing leg blocking it is the actual root cause of the stable
promotion backlog, not whatever else changed between the frozen digest and
`main` HEAD. Fixing only the other legs' known issues will not move
`:testing` or unblock `Execute Release` until that leg passes.
## `:testing` can carry a stream tag even when `promote-to-testing` is skipped

Do not assume the bare `:testing` tag only ever moves through
`promote-to-testing` in `post-testing-e2e.yml`. `build-image-testing.yml`
passes `publish_stream_tag: "false"` to
`projectbluefin/actions/.github/workflows/reusable-build.yml@v1` specifically
so a `main`/`testing`-branch build does not publish the bare stream tag ahead
of the e2e gate — but this repo does not control whether that input is
actually honored by the push step in that reusable workflow.

Reported on #989 (2026-08-07): the digest tagged `:testing` in the registry
was the exact digest a `run-e2e` run had just failed against, in a run where
`promote-to-testing` was `skipped`. That means either `compute-push-tags`'
excluded-tag output was not honored by the later push step, or something else
in the reusable workflow re-tags after the fact (for example `just
tag-images` tagging `DEFAULT_TAG` locally and a later step publishing all
local tags regardless of the computed set).

Before trusting `promote-to-testing: skipped` as proof `:testing` is still
the last known-good digest, verify what the registry actually serves:

```bash
skopeo inspect docker://ghcr.io/projectbluefin/bluefin:testing
```

Compare the returned digest against the `IMAGE:` value logged by the most
recent `run-e2e` run for that digest. A mismatch, or a match against a
*failing* run, means the leak reproduced again. The fix (making
`publish_stream_tag: "false"` actually prevent the bare-tag push, plus a
regression guard) belongs in `projectbluefin/actions`, not here — this repo
only supplies the input; it does not control the push step that is supposed
to honor it.
