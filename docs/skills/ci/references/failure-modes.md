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
