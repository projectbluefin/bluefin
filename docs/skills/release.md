# Release Workflow and Stream Promotion

## When to Use

- Promoting `:testing` to `:stable`
- Diagnosing why `execute-release.yml` did not publish or published incomplete notes
- Recovering from release-notes failures in `reusable-release.yml@v1`

## When NOT to Use

- Routine PR validation and unit test failures → [build.md](build.md)
- Renovate workflow behavior → [renovate.md](renovate.md)
- ISO pipelines → [iso.md](iso.md)

## Core Process

1. Confirm promotion actually happened (`testing` -> `main` squash commit exists and `execute` job passed).
2. Inspect `release-notes` in `execute-release.yml` and verify it calls `projectbluefin/actions/.github/workflows/reusable-release.yml@v1`.
3. Treat SBOM artifact download as best-effort: `actions/download-artifact@v8` errors if artifact name is missing, so reusable-release must handle that path without blocking publication.
4. If release was created with incomplete package data, delete the release tag entry (not git tag) and rerun `execute-release.yml` via `workflow_dispatch`.
5. Verify the newest `stable-*` release includes expected assets/body sections and that `post-release-variants` succeeded.

## Release Flow

```text
PR merges to testing
  -> build-image-testing.yml
  -> promote-testing-to-main.yml (auto/promote-testing-to-main PR)
  -> merge queue -> squash to main
  -> execute-release.yml
     - execute: reusable-execute-release.yml@v1 (:testing -> :stable)
     - release-notes: reusable-release.yml@v1 (SBOM + release body/assets)
```

## Current `execute-release.yml` contract

`release-notes` must stay on artifact mode for bluefin:

```yaml
release-notes:
  uses: projectbluefin/actions/.github/workflows/reusable-release.yml@v1
  with:
    generate_sbom_inline: false
    build_workflow: build-image-testing.yml
    build_branch: testing
    sbom_artifact: sbom-bluefin
```

## Common Failure Modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `release-notes` fails on artifact lookup | Named artifact is missing in selected build run | Use reusable-release artifact fallback (in `actions@v1`), then rerun execute-release |
| Release succeeds but package table is empty/near-empty | Fallback SPDX stub was used because artifact was missing | Trigger a fresh build that uploads SBOM, then rerun execute-release |
| `release-notes` skipped | `check-trigger` filtered a non-promotion push | Use `workflow_dispatch` |
| Release appears unchanged after rerun | Tag already existed and create-release short-circuited | Delete release entry first, rerun |

## Re-run Procedure

```bash
# delete only the GitHub Release object for that tag
gh release delete <stable-tag> --repo projectbluefin/bluefin --yes

# rerun release pipeline from main
gh workflow run execute-release.yml --repo projectbluefin/bluefin --ref main
```

## Daily publish-time evidence (testing + stable)

Use package-version timestamps as publish evidence for user-visible tags:

```bash
for pkg in bluefin bluefin-nvidia; do
  json=$(gh api --paginate "orgs/projectbluefin/packages/container/${pkg}/versions?per_page=100" | jq -s 'add')
  for stream in testing stable; do
    row=$(jq -r --arg s "$stream" '[.[] | select(((.metadata.container.tags // []) | index($s)) != null)] | sort_by(.created_at) | last // empty | @base64' <<<"$json")
    obj=$(echo "$row" | base64 -d)
    created=$(jq -r '.created_at' <<<"$obj")
    et=$(TZ=America/New_York date -d "$created" '+%Y-%m-%d %I:%M:%S %p %Z')
    echo "${pkg} ${stream} ${et} $(jq -r '.html_url' <<<"$obj")"
  done
done
```

Interpretation rule:
- `created_at` is the package-version publish timestamp (UTC); convert with `TZ=America/New_York` for ET reporting.
- Report both streams (`testing`, `stable`) for both images (`bluefin`, `bluefin-nvidia`) with package-version URL evidence.

## Common Rationalizations

- "Artifact mode is configured so artifact must exist."
  `download-artifact@v8` errors when a named artifact is absent; plan for that case.
- "Release succeeded, so package inventory is trustworthy."
  A fallback SBOM can still produce a green job; verify package data quality, not only job status.
- "One manual rerun fixed it, we can stop documenting this."
  If it happened once in automation, encode the behavior in this skill.

## Red Flags

- `generate_sbom_inline: true` reintroduced in bluefin release-notes path
- `release-notes` green but release body has empty/minimal package data
- Repeated same-day release reruns without deleting existing broken release entry
- Any docs claiming `sbom-bluefin` is guaranteed in every selected build run

## Verification

- [ ] `execute-release.yml` completed with `execute`, `release-notes`, and `post-release-variants` green
- [ ] Latest `stable-*` release exists and has release-card + SPDX asset
- [ ] Release body contains a populated package inventory (not fallback-empty)
- [ ] Docs in this file match the current `execute-release.yml` inputs

## Sources

- Context7: `/actions/download-artifact` (artifact-name lookup errors if missing)
- Context7: `/websites/github_en_actions` (`steps[*].continue-on-error` behavior)
- Context7: `/websites/github_en_rest` (org package-version API fields: `created_at`, `metadata.container.tags`)
