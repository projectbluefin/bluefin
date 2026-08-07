# CI failure triage

Reference for [`../SKILL.md`](../SKILL.md). Always inspect the failed run logs
before changing a workflow.

## Triage table

| Symptom | First check |
|---|---|
| No checks at all | PR base branch (must be `testing`) and, for fork PRs, maintainer approval |
| Workflow did not trigger | Event, branch, and `paths-ignore` filters in the YAML |
| Validation differs locally | `just check` and `pre-commit run --all-files` |
| Promotion is blocked | Exact digest, required check, and merge-group state |
| Dependent job `skipped` | An upstream `needs:` job failed without `always()` |
| Reusable workflow behaves incorrectly | The workflow in `projectbluefin/actions`, not the caller |

## Fork pull requests report zero checks

A pull request whose head branch lives on a fork reports **zero** checks until a
maintainer approves the run. That looks identical to "checks still queued", so
confirm the state before waiting on it:

```bash
gh pr view PR --repo projectbluefin/bluefin --json headRepositoryOwner,maintainerCanModify
gh api -X POST repos/projectbluefin/bluefin/actions/runs/RUN_ID/approve
```

`maintainerCanModify: true` also means fix commits can be pushed straight to the
contributor's branch.

## A `type: string` input is always truthy

A `type: string` input is truthy in an `if:` even when its value is `"false"`.
Gating on the bare input therefore fails **open**. Compare explicitly and treat
any unexpected value as the safe state:

```yaml
if: inputs.publish_stream_tag == 'true'
```

## Reusable-workflow calls cannot be advisory

A job that calls a reusable workflow accepts only `name`, `uses`, `with`,
`secrets`, `needs`, `if`, and `permissions`. `continue-on-error` and `runs-on`
are rejected, so a reusable-workflow call either gates or is absent.
`actionlint` catches this.

## `needs:` without `always()` hides failures

A job listed in `needs:` without `always()` makes its dependents `skipped` when
it fails. Confirm whether a promotion job is *failing* or *never running*; the
two look the same in the UI and have different fixes.

`build-image-testing.yml` and `pr-validation.yml` both use
`if: always() && …` for exactly this reason.

## `cmd | tee file` masks the exit status

`cmd | tee results.tap` reports the exit status of `tee`, not of `cmd`. GitHub's
default shell for a bare `run:` block is `bash -e {0}` — **without** `pipefail`.
Set `shell: bash` (which adds `-o pipefail`) or check `PIPESTATUS` whenever a
test command is piped. `pr-validation.yml`'s `Run unit tests` step pipes `bats`
into `tee`; treat that as a live trap when editing the job.

## BATS coverage instrumentation (`pr-validation.yml` → `unit-tests`)

- The job publishes `bats-tap-results` and `bats-kcov-report` artifacts.
- kcov is not packaged for Ubuntu 24.04, so the job builds v43 from a pinned,
  SHA-256-verified source archive and caches it under `~/.cache/bluefin-kcov`.
- Coverage runs route child `bash <script>` calls through
  `tests/coverage/bin/bash`; wrapping only the top-level BATS process does not
  trace those child shells. The wrapper records each sandbox copy's original
  source path, and `tests/coverage/merge_kcov.py` combines those hits with
  kcov's pre-parsed source inventory.
- The coverage run **must** redirect BATS output to a file
  (`> coverage/bats-coverage-run.tap`): kcov captures child stdout through a
  pipe it stops draining, so streaming the full TAP log through it deadlocks
  the job.
- The instrumented rerun does not gate the job — `Run unit tests` owns
  pass/fail — but `merge_kcov.py` fails when no source lines were executed.
  A zero-line report is an instrumentation failure, not "no coverage".
- Tests that `source` a library into the BATS process itself are not traced.

## Containerfile bind mounts poison the build cache

Containerfile stages that consume source through bind mounts inherit the mounted
stage's image ID as part of their cache key. `Containerfile` gives the package
stage its own narrow `scratch` context (`ctx-build`) so unrelated `system_files`
edits do not invalidate it, and passes `BUILD_FILES_SHA` as a second explicit
guard. See [build](../../build/SKILL.md).

## Verification

```bash
# Reproduce the pipefail trap and the kcov steps
sed -n '/unit-tests:/,/testsuite:/p' .github/workflows/pr-validation.yml

# Confirm the always() guards
grep -n 'always()' .github/workflows/*.yml

# Confirm the cache split
grep -n 'ctx-build\|BUILD_FILES_SHA' Containerfile
```
