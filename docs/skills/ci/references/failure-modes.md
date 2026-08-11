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
