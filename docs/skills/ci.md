# CI/CD Troubleshooting

## When to use

- A GitHub Actions workflow failed
- A PR has no checks or the wrong checks
- Testing/stable/latest promotion behavior looks wrong
- Release generation or automerge is stuck

## When NOT to use

- Pure local validation issues → [build.md](build.md)
- Package placement decisions → [packages.md](packages.md)
- ISO pipeline work in the separate repo → [iso.md](iso.md)

## First triage

List recent runs:
```bash
gh run list --repo projectbluefin/bluefin --limit 20
```

Inspect a failed run:
```bash
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
```

Retry only failed jobs:
```bash
gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
```

## Workflow map

| Workflow | Purpose |
|---|---|
| `pr-validation.yml` | PR gate on `testing` |
| `build-image-testing.yml` | build testing images from `main` |
| `post-testing-e2e.yml` | smoke-test current `main` testing image |
| `weekly-testing-promotion.yml` | promote tested `main` to `latest` + `stable` |
| `build-image-stable.yml` | build `stable` images |
| `build-image-latest-main.yml` | build `latest` images |
| `generate-release.yml` | create stable GitHub release text/assets |
| `renovate-automerge.yml` | auto-merge passing Renovate PRs |
| `validate-renovate.yml` | validate `.github/renovate.json5` |

## Fast checks by symptom

### PR has no CI
- Confirm the PR targets `testing`
- Confirm the changed files are not excluded by workflow path filters
- Re-open or retarget the PR if needed

### `just check` failed in CI
```bash
just check
```

### pre-commit failed in CI
```bash
pre-commit run --all-files
```

### shellcheck failed in CI
```bash
shellcheck build_files/**/*.sh
```

## Promotion pipeline mental model

1. Push to `main`
2. `build-image-testing.yml` publishes testing images
3. `post-testing-e2e.yml` smoke-tests that exact digest
4. `weekly-testing-promotion.yml` verifies the same `main` SHA still passed e2e
5. Promotion fast-forwards `latest` and `stable`
6. Branch-specific build workflows rebuild those streams

If `main` advanced during promotion, the workflow aborts on purpose.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `startup_failure` with zero jobs | unsupported permissions scope in that environment | compare `permissions:` with a known-good upstream run |
| `No SBOM referrer found` in release generation | one side of the diff has no attached SBOM | allow missing SBOMs for diff generation and use intersection-only comparisons |
| promotion says no passing e2e for current SHA | `post-testing-e2e` has not passed the locked `main` commit | wait or rerun after e2e completes |
| required check is skipped | path filter skipped the workflow | verify whether skipped is intentional for that workflow |
| Renovate PR did not automerge | PR lookup missed mergeraptor author or wrong base branch | accept both Renovate and mergeraptor authors; verify branch targeting |

## Non-obvious patterns

- `post-testing-e2e.yml` is the continuous gate; weekly promotion assumes it already passed on the exact `main` SHA
- A skipped workflow can still satisfy a required check if GitHub considers it skipped-by-filter
- Stable release generation depends on SBOM assets existing for the images being diffed
- Bluefin docs-only changes often skip image builds due to path filters; that is usually expected

## Lessons learned

<!-- Add reusable CI/debugging patterns here -->
