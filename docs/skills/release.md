# Release Workflow and Stream Promotion

## When to use

- Promoting tested `main` builds to `latest` and `stable`
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
     -> fast-forward latest + stable
     -> trigger build-image-latest-main.yml
     -> trigger build-image-stable.yml
     -> generate-release.yml (stable)
```

## Key workflows

| Workflow | What it does |
|---|---|
| `post-testing-e2e.yml` | smoke-tests the current testing image digest |
| `weekly-testing-promotion.yml` | promotes only if the current `main` SHA already passed e2e |
| `build-image-stable.yml` | rebuilds stable and calls release generation |
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
gh workflow run build-image-stable.yml --repo projectbluefin/bluefin --ref stable
gh workflow run build-image-latest-main.yml --repo projectbluefin/bluefin --ref latest
```

## Release checklist

1. `main` testing image build passed
2. `post-testing-e2e.yml` passed on the exact `main` HEAD
3. weekly promotion completed without `main` advancing underneath it
4. stable build finished cleanly
5. `generate-release.yml` created the release and attached SBOM assets

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| promotion aborts because SHA changed | new commit landed on `main` during gate | rerun promotion later |
| promotion says nothing to do | `main` and `latest` are identical | no action needed |
| stable release generation fails on SBOM lookup | older compared image lacks SBOM referrer | use missing-SBOM-safe changelog logic |
| latest/stable moved without intended coverage | bypassed the testing gate | use workflow-driven promotion, not manual retagging |

## Non-obvious patterns

- `weekly-testing-promotion.yml` locks the current `main` SHA first, then verifies the gate on that exact commit
- Stable releases are generated from workflow output; do not hand-edit release notes as the primary source of truth
- ISO release and promotion is a **different repo**: `projectbluefin/bluefin-iso`

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

## Lessons learned

<!-- Add reusable release/promotion patterns here -->
