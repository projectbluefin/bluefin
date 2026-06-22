# Release Workflow and Stream Promotion

## When to use

- Promoting `:testing` builds to `:stable`
- Generating stable release notes
- Understanding which workflow moves which stream
- Checking why a promotion or release did not happen

## When NOT to use

- Routine PR work → [build.md](build.md)
- Renovate-specific dependency PR handling → [renovate.md](renovate.md)
- ISO release work in the separate repo → [iso.md](iso.md)

## Current release flow

```text
main push
  -> build-image-testing.yml
  -> post-testing-e2e.yml
  -> weekly-testing-promotion.yml
     -> retag :testing digests → :stable
     -> generate-release.yml (stable)
```

## Key workflows

| Workflow | What it does |
|---|---|
| `post-testing-e2e.yml` | smoke-tests the current testing image digest |
| `weekly-testing-promotion.yml` | promotes only if the current `main` SHA already passed e2e; retaggs digests to `:stable` |
| `generate-release.yml` | runs `just changelogs stable` and publishes the GitHub release |

## Generate changelog locally

```bash
just changelogs stable
just changelogs stable "optional handwritten notes"
```

Artifacts written locally:
- `output.env`
- `changelog.md`

## Trigger workflows manually

```bash
gh workflow run weekly-testing-promotion.yml --repo projectbluefin/bluefin
```

To re-generate a release manually:

```bash
gh workflow run generate-release.yml \
  --repo projectbluefin/bluefin \
  --field stream_name='["stable"]' \
  --field handwritten="optional notes"
```

## Release checklist

1. `main` testing image build passed
2. `post-testing-e2e.yml` passed on the exact `main` HEAD
3. weekly promotion completed without `main` advancing underneath it
4. `generate-release.yml` created the release and attached SBOM assets

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| promotion aborts because SHA changed | new commit landed on `main` during gate | rerun promotion later |
| `generate-release.yml` fails with "not enough tags" | first-ever release: `changelogs.py` needs ≥ 2 stable tags; fixed by bootstrap patch (PR #264) | ensure the bootstrap fix is merged; or dispatch `generate-release.yml` manually |
| stable moved without intended coverage | bypassed the testing gate | use workflow-driven promotion, not manual retagging |

## Non-obvious patterns

- `weekly-testing-promotion.yml` locks the current `main` SHA first, then verifies the gate on that exact commit
- Stable releases are generated from workflow output; do not hand-edit release notes as the primary source of truth
- ISO release and promotion is a **different repo**: `projectbluefin/bluefin-iso`
- `changelogs.py` requires ≥ 2 stable tags in GHCR to compute an RPM diff; the very first release has only 1 tag and the script exits 1 unless the bootstrap fix (PR #264) is present

## Shared release action

The `bootc-build/generate-release` action standardizes release note generation:

```yaml
- uses: projectbluefin/actions/bootc-build/generate-release@v1
  with:
    image: ghcr.io/projectbluefin/bluefin
    previous-tag: stable-previous
    current-tag: stable
```

It produces:
- RPM diff (added/removed/upgraded packages)
- SBOM comparison
- Formatted changelog markdown

This replaces per-repo `just changelogs` wrapper scripts in CI with a standardized action.
