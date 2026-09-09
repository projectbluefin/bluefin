# CI failure triage

| Symptom | First check |
|---|---|
| No checks | Pull request base branch and path filters |
| Validation differs locally | Run `just check` and `pre-commit run --all-files` |
| Workflow did not trigger | Event, branch, and path filters in the YAML |
| Promotion is blocked | Exact digest, required check, and merge-group state |
| Promotion conflict (GH006) | Check if promotion PR is in merge queue; wait for queue cycle |
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

## Promotion conflict caused by merge-queue branch locking (GH006)

When `promote-testing-to-main.yml` fails and opens an issue titled
`ci: testing→main promotion conflict`:

```bash
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
```

If the log reports:

```text
remote: error: GH006: Protected branch update failed for refs/heads/auto/promote-testing-to-main.
remote: - A pull request for this branch has been added to a merge queue. Branches that
remote:   are queued for merging cannot be updated. To modify this branch, dequeue the
remote:   associated pull request.
remote: error: failed to push some refs to 'https://github.com/projectbluefin/bluefin'
```

### Cause

1. `promote-testing-to-main.yml` invokes
   `projectbluefin/actions/.github/workflows/reusable-promote-squash.yml` with
   `use_merge_queue: true`.
2. When the promotion PR (`auto/promote-testing-to-main`) is enqueued via
   `enqueuePullRequest`, GitHub places a branch protection lock on
   `auto/promote-testing-to-main` while it awaits merge group execution.
3. If an intermediate commit is pushed to `testing` while the PR is in the queue,
   the push triggers a new `promote-testing-to-main.yml` run.
4. Because the tree on `testing` has changed, `reusable-promote-squash.yml`
   attempts `git push --force origin "$PROMOTION_BRANCH"` to update the squash PR.
5. GitHub's protected branch hook declines the update with error `GH006`.
6. The `promote` job fails, and `report-failure` creates or updates a conflict
   issue titled `ci: testing→main promotion conflict`.

### Resolution

- **This is not a git merge conflict.** The code trees merge cleanly without
  conflict markers.
- **Do not manually force-close or create empty commits.** Once the queued PR
  merges or times out from the merge queue (ruleset 17070404 specifies a
  120-minute timeout), the next promotion run succeeds.
- The `close-failure-issue` job in `reusable-promote-squash.yml` automatically
  closes the conflict issue on the next successful run.

## Stable promotion pipeline resolved (2026-09-09)

The 51-day stable pipeline stall (#929) was resolved with the publication of release
[`stable-20260909`](https://github.com/projectbluefin/bluefin/releases/tag/stable-20260909).

### Root cause chain

1. **`post-testing-e2e.yml` branch filter block**:
   `promote-to-testing` was previously guarded with `github.event.workflow_run.head_branch == 'main'`.
   Because `Testing Images` builds on `testing`, `promote-to-testing` was skipped on every successful build,
   leaving `:testing` pointing at the August 4 build (`sha256:bf615b20...`) for 51 days.
   **Fix**: Guard was updated to allow promotion on tested builds, and `workflow_dispatch` added with `skip_e2e` support.
2. **`post-testing-e2e.yml` concurrency cancellation**:
   `cancel-in-progress: true` caused subsequent pushes or workflow runs to kill in-progress E2E suites.
   **Fix**: Switched to `cancel-in-progress: false` with run-scoped concurrency group.
3. **`testsuite` E2E regressions on GNOME 50**:
   - Dash to Dock gdbus regex updated for float/uint format matching.
   - Portal timeout in container runners eliminated by masking `xdg-desktop-portal.service`.
   - Firefox window resolution updated to top-level browser chrome windows with non-blocking `tree.root.applications()` closure check.
   - Tab count asserts replaced with resilient fallbacks for headless/flatpak environments.
   - SSH `ControlMaster=no` with keepalive configured in `e2e.yml` to prevent TCP drops during long behave runs.
   - Bootc status `opendir(boot)` handled gracefully on bare-kernel QEMU test environments.
4. **`actions#463` and `testsuite#792` merged**:
   Both repositories advanced on their managed `v1` tags, unblocking CI promotion to `:testing` and `Execute Release` to `:stable`.

| Field | Value |
|---|---|
| `:testing` digest | `sha256:bf615b20…` — unchanged since this was first reported on 2026-08-07 |
| `org.opencontainers.image.version` | `testing-44.20260804` |
| `org.opencontainers.image.created` | `2026-08-04T15:59:11Z` |

That build predates `common#966` by five days, so it ships the previous
`update.just` (`bd90527`, 2026-06-20).

**Why the `@requires_toggle_action` gate did not skip.** The pre-`#966` recipe
already declared `toggle-updates ACTION="prompt"` — it *accepts* the argument
and then ignores it, falling straight through to the interactive body. So the
probe `ujust toggle-updates cancel` reaches `gum choose`, which fails with no
TTY and leaves `SELECTED_OPTION` empty, and the next line is

```bash
[[ "${SELECTED_OPTION}" == "Cancel" || "${SELECTED_OPTION}" == "" ]] && exit 0
```

which exits `0`. The gate meant to skip images lacking ACTION support passes on
exactly those images, so the scenario runs and fails. An exit-status probe
cannot detect this contract; it has to observe the behaviour (that `enable`
actually changes timer state) or inspect the recipe body. That is the only part
of this thread that is still a bug — report it to `projectbluefin/testsuite`.

**Consequence: `common-b` is not an independent blocker.** It is an artifact of
the freeze and needs no change in `bluefin`. This repo's `common` pin in
`image-versions.yml` is bumped by Renovate near-daily, has carried `#966` since
#1069 (2026-08-09), and is current as of #1146 (2026-08-28) — so any newly
built image satisfies the scenario. The leg goes green on its own once a fresh
image is promoted. Do not chase it as a product regression, and do not count it
when deciding what still has to be fixed to unfreeze `:testing`.

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

# ...and when that digest was built. The age is what settles "is this image
# older than the fix I am looking for?" — a tag that has not moved in days is
# frozen, and its failures describe that old build, not the current tree.
skopeo inspect docker://ghcr.io/projectbluefin/bluefin:testing \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["Labels"]["org.opencontainers.image.version"], d["Created"])'

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
## `promote-testing-to-main` fails with `GH006` while another run is enqueuing

`.github/workflows/promote-testing-to-main.yml` calls
`projectbluefin/actions/.github/workflows/reusable-promote-squash.yml@v1`,
which force-pushes the rebuilt squash branch and then calls the
`enqueuePullRequest` GraphQL mutation because `use_merge_queue: true`. If two
triggers land close together (a `push` to `testing` and the daily `schedule`,
or two pushes to `testing` moments apart), one run can finish enqueuing before
the other's force-push lands, and the later run fails with:

```
remote: error: GH006: Protected branch update failed for refs/heads/auto/promote-testing-to-main.
remote: - A pull request for this branch has been added to a merge queue. Branches that
remote:   are queued for merging cannot be updated. To modify this branch, dequeue the
remote:   associated pull request.
```

This is noise, not a lost promotion: the workflow's `concurrency` group
serializes runs, and the earlier run already reached the intended state
(branch pushed, PR enqueued). Confirm with the promotion PR's timeline before
treating the failed run as a real blocker:

```bash
gh pr view <promotion-pr> --repo projectbluefin/bluefin --json number \
  --jq '.number' | xargs -I{} gh api repos/projectbluefin/bluefin/issues/{}/timeline \
  --jq '.[] | select(.event | test("force_pushed|merge_queue")) | [.event, .created_at]'
```

Interleaved `head_ref_force_pushed` / `added_to_merge_queue` events around the
same minute confirm this benign race. The retry logic that would need to
change (retry the enqueue instead of failing outright) lives in
`reusable-promote-squash.yml` in `projectbluefin/actions`, not in this repo's
thin caller — do not add push-retry logic here.

The GitHub merge queue itself removes a queued PR once its required checks
resolve, including the release-gate check that re-runs the E2E suite against
the squashed result. A promotion PR that cycles `added_to_merge_queue` then
`removed_from_merge_queue` roughly two hours later, day after day, means the
release gate is genuinely failing on the squashed content — diagnose the
underlying E2E failure (see above), not the promotion workflow, in that case.
## `:testing` promotion blocker set (issue #989) — re-verified 2026-08-27

`run-e2e / smoke,common / GNOME 50 — smoke-a` has failed on essentially every
`post-testing-e2e` run since 2026-06-25, making `promote-to-testing` `skipped`
(it needs `run-e2e.result == 'success'`). The root cause and fix are **owned by
`projectbluefin/testsuite`**, not this repo — bluefin ships Firefox as an
unmodified RPM and no bluefin-side change correlates with the regression
window. Do not attempt to work around this from `bluefin` by adding
`always()`, `continue-on-error`, or dropping `run-e2e` from
`promote-to-testing`'s `needs:` — that would promote an unverified digest.

State as of Nightly E2E run
[33036921142](https://github.com/projectbluefin/bluefin/actions/runs/33036921142)
(2026-08-27T03:37Z):

- All six `firefox.feature` scenarios still fail deterministically, through
  both `@retry` passes. The initial run and both retries report zero Firefox
  scenarios passed, with `AssertionError: Firefox address bar not found` (and
  the matching tab-list / "still visible" assertions for the Ctrl+T / Ctrl+W /
  Ctrl+Q scenarios).
- `testsuite#692` (merged 2026-08-07, in the current `v1` tag) fixed the
  original bug: Firefox launched without `GNOME_ACCESSIBILITY=1`, so its
  AT-SPI subtree never populated, and `_firefox_window()` falsely accepted a
  bare `filler` node as a healthy window. That fix is real but **incomplete**:
  the "main window is accessible" step now passes because the window exposes
  *some* populated chrome (for example a toolbar or push button), but the
  address-bar `entry` node specifically still never appears, so
  `_address_bar()` still raises.
- `testsuite#741` merged 2026-08-26 and is conclusively **not** the remaining
  fix. The run above resolved both the reusable workflow and `test_ref` to
  testsuite commit `ee82d53`, which contains `#741`'s merge commit, yet the
  failure reproduced unchanged. That PR forwards `FIREFOX_A11Y_ENV` through
  exported Flatpak desktop launches, but testsuite checks the `firefox` command
  before its Flatpak candidates. Bluefin's base package manifest and image
  validation require the Firefox RPM, so that command candidate is available
  first; the Flatpak-export path changed by `#741` is not selected.
- Continue the fix in `projectbluefin/testsuite`: log the selected
  `context.firefox_launch_target` and dump the Firefox AT-SPI subtree on
  failure, then correct the RPM-command path from that live evidence. Do not
  guess at another Bluefin workflow bypass or treat a later `#741` merge as
  evidence that the gate is fixed.
- A post-testing rerun has not yet validated the updated testsuite because
  every qualifying `Testing Images` run since 2026-08-12 has failed before E2E
  (tracked separately in `#995`). The first successful push build will trigger
  `post-testing-e2e.yml` automatically.
- Unblock criterion: one green `Post-Testing E2E` run with
  `promote-to-testing: success` after the testsuite fix lands closes this
  issue. There is nothing to change in `bluefin` itself beyond re-verifying
  that run.

## `Testing Images` itself has been failing since 2026-08-12 — `post-testing-e2e` now skips before e2e even runs

The AT-SPI/`firefox.feature` blocker documented above (issue #989,
re-verified 2026-08-10) is no longer the proximate blocker on `:testing`.
Every `Testing Images` run from
[31607601482](https://github.com/projectbluefin/bluefin/actions/runs/31607601482)
(2026-08-12T14:35Z) through
[32753582407](https://github.com/projectbluefin/bluefin/actions/runs/32753582407)
(2026-08-24T16:54Z–18:01Z, re-verified live) has failed before there is an
image to test — 9 consecutive failures over 12 days, zero successes.
Confirmed run IDs: `31607601482`, `31727537250`, `31892823167`,
`32190444084`, `32190579865`, `32257399479`, `32341452980`, `32346294695`,
`32753582407`.

Both `bluefin` and `bluefin-nvidia` (`main`/`nvidia` flavor) fail identically,
on every retry within a run, at the same step — the `extension-builder` stage
in `Containerfile` (`dnf5 -y install glib2-devel meson sassc cmake
dbus-devel`, right after the `base-common` stage completes):

```
error: rpmdb: damaged header #1808 retrieved -- skipping.
error: SELECT hnum, blob FROM 'Packages': 11: database disk image is malformed
Transaction failed: Rpm transaction failed.
```

The damaged header number is not perfectly stable (`#1808` on 08-20,
`#1809` on the 08-24 re-check), so this is not one static, byte-identical
cached blob being replayed forever — treat it as "reliably corrupts the same
way," not "the exact same bytes every time," when investigating.

`Containerfile` and `image-versions.yml` have not changed since 2026-08-07
(before the last known-good build on 2026-08-10), which rules out a
script/pin regression as the direct trigger — something external to those
files changed between the 08-10 success and the 08-12 failure.

Because `post-testing-e2e.yml`'s `e2e` job requires
`github.event.workflow_run.conclusion == 'success'`, every `Post-Testing E2E`
run since 08-12 reports `skipped` for `e2e`, `run-e2e`, and
`promote-to-testing` — not `failure`. The AT-SPI triage above still describes
a real, unfixed bug, but it is not what is currently stopping `:testing` from
advancing: the pipeline no longer gets far enough to reach it.

**Unconfirmed prime suspect** (flag for whoever picks this up next; not
proven here — this runtime has no CI trigger access and per policy
documentation changes should not run expensive image builds to test it):
the registry-based buildah layer cache. `Justfile`'s `build` recipe computes
`cache_ref="ghcr.io/{{ repo_organization }}/${image_name}"`, keyed only by
flavor (`bluefin` / `bluefin-nvidia`), not by tag, and both `--cache-from`
(every build) and `--cache-to` (every non-PR push) target that one ref. A
`testing`-branch push and the `main`-branch push that
`promote-testing-to-main` triggers minutes later both build the `main` flavor
and can run concurrently, writing `--cache-to` the identical ref; a bad
interleaving there could plausibly corrupt a cached `base-common` layer that
every later `--cache-from` then keeps replaying, matching the observed
determinism across flavors and retries (the damaged-header number drifting
by one between checks is consistent with a stable corrupted layer plus
normal package-set churn, not proof against this). Before assuming this: get
a maintainer to trigger one build with the registry cache disabled
(`--cache-from`/`--cache-to` both suppressed, not just `REGISTRY_CACHE_WRITE=0`,
which still reads the poisoned cache) and compare.

```bash
# Reproduce the census
gh run list --repo projectbluefin/bluefin --workflow "Testing Images" -L 20 \
  --json conclusion,createdAt,headBranch,databaseId

# Confirm post-testing-e2e is skipping, not failing, e2e
gh run view RUN_ID --repo projectbluefin/bluefin --json jobs \
  --jq '.jobs[] | [.name, .status, .conclusion] | @tsv'
```

### Update 2026-08-28 — registry-cache suspect disproven; failure is a WAL-mode rpmdb read across the stage-commit boundary

Full-log forensics across the good/bad boundary correct two claims above and
retire the prime suspect:

- **The census conflates two failure modes.** Run `31607601482` (08-12) built
  every stage successfully — including the `extension-builder` dnf install —
  and failed only while *pushing* (GHCR secondary rate limit, HTTP 403, on
  both the cache push and the image push). The rpmdb-malformed signature
  starts with `31727537250` (08-13) and appears in every failing run from
  then on. Last good *build* is therefore 08-12, not 08-10.
- **The registry-cache-replay suspect is disproven.** The failing step's
  parent (`base-common`) rebuilds fresh in the failing runs — its `FROM`
  digest is re-resolved daily, so its cache key changes daily, and run
  `32924887367` (08-26) demonstrably executed Stage 1 live (new
  `BUILD_FILES_SHA`, full 251-package install in the log) and still failed.
  Seven distinct daily base digests (08-13 → 08-26) all fail identically; no
  stale cached layer is involved. Do not ask a maintainer for a cache-disabled
  run; that experiment answers a question this evidence already settles.
- **Environment is constant across the boundary.** Last-good (08-12) and
  first-bad (08-13) runs used the identical runner image (`20260720.247.2`),
  identical podman/buildah/crun from Ubuntu resolute
  (5.7.0 / 1.42.1 / 1.21), a `projectbluefin/actions` delta touching only
  sync-branches/renovate workflows, and a bluefin delta touching only
  `20-tests.sh` (runs in Stage 2, after the failing step).
- **The base composes are package-identical.** `44.20260812.0` (works) and
  `44.20260813.0` (fails) have byte-identical `rpm -qa` sets and
  byte-identical shipped `rpmdb.sqlite-shm`/`-wal` sidecars. Only the
  `rpmdb.sqlite` bytes and layer packing differ.
- **What is actually failing:** the Fedora bootc bases ship
  `/usr/lib/sysimage/rpm/rpmdb.sqlite` in SQLite **WAL journal mode** with
  stale `-shm`/`-wal` sidecars, and every dnf transaction in a build stage
  leaves the database in WAL mode with fresh sidecars. The
  `extension-builder` failure is the next stage's *first read* of that
  committed WAL state (`SELECT hnum, blob FROM 'Packages'` is the rpmdb
  Packages table): under CI's rootful buildah 1.42.1 overlay it reports
  SQLITE_CORRUPT, while the same image and same read succeed under local
  rootless podman 5.8.4 — the residual trigger is in the
  buildah-version/overlay interaction with post-0812 rpmdb bytes, not in any
  input this repo pins.
- **Fix applied in this repo:** `build_files/shared/checkpoint-rpmdb.sh`
  checkpoints the WAL, converts the rpmdb to the default rollback-journal
  mode, and removes the sidecars; `Containerfile` runs it as the last step of
  Stage 1 and Stage 2, so every committed layer (and the shipped image)
  carries a single self-contained `rpmdb.sqlite`. Validated locally: with the
  checkpoint in place, a two-stage build on the failing-era base commits a
  sidecar-free `journal_mode=delete` database that the next stage reads and
  installs against cleanly; without it, a stage's dnf write always re-enables
  WAL, which is why the script must run per-stage, not once.

### Update 2026-09-06 — `Testing Images` builds again; `post-testing-e2e` reaches `run-e2e` and reproduces the unchanged `firefox.feature` blocker

The `checkpoint-rpmdb.sh` fix above has held: `Testing Images` builds are
succeeding again, so `post-testing-e2e` no longer skips before `e2e` runs.
Run [34008857087](https://github.com/projectbluefin/bluefin/actions/runs/34008857087)
(2026-09-06T03:23Z) confirms this — `e2e` ran and `run-e2e / smoke,common /
GNOME 50 — smoke-a` failed, not skipped.

That run resolved `projectbluefin/testsuite/.github/workflows/e2e.yml@v1` to
commit `ee82d53` — the same commit already assessed on 2026-08-27 above — and
`gh api repos/projectbluefin/testsuite/git/refs/tags/v1` today points to
`3a8c79a`, whose only commits since `ee82d53` are dependency bumps and an
unrelated behave-suite-environment refactor (`#765`); none touch
`firefox_steps.py` or `firefox.feature`. **No testsuite fix for the RPM-vs-Flatpak
launch-target gap identified on 2026-08-27 has landed or is open** (checked
both merged and open PRs/issues in `projectbluefin/testsuite` for `firefox`/
`AT-SPI`/`address bar` as of this update).

All six `firefox.feature` scenarios still fail identically through both
`@retry` passes, same signature as every prior check:

```
STEP_ERROR ['Address bar is present in Firefox']: AssertionError: Firefox address bar not found
    assert matches or bars, "Firefox address bar not found"
AssertionError: Firefox address bar not found
```

Nothing has changed in `bluefin` to correlate with this, and there is still
nothing to change here — the fix remains scoped to
`projectbluefin/testsuite`'s Firefox launch-target selection (log
`context.firefox_launch_target` and prefer/patch the RPM `firefox` command
path so the AT-SPI env actually reaches the process that gets a window,
per the 2026-08-27 analysis). Re-verify against the next `post-testing-e2e`
run once a testsuite PR addressing that gap merges.
