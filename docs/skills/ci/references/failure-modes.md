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
