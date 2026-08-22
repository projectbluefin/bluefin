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
