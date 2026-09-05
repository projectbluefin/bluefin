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
