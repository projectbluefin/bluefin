# Release Workflow and Stream Promotion

## When to use

- Promoting `:testing` builds to `:stable`
- Diagnosing why a release has missing SBOM or package information
- Re-triggering a failed or incomplete release
- Understanding the centralized release action in `projectbluefin/actions`

## When NOT to use

- Routine PR work → [build.md](build.md)
- Renovate dependency handling → [renovate.md](renovate.md)
- ISO release work → [iso.md](iso.md)
- LTS stream specifics → `projectbluefin/bluefin-lts` repo

## Current release flow

```text
PR merges to testing
  → build-image-testing.yml (Testing Images)
      └─ reusable-build: builds image, generates SBOM while layers are local,
         uploads sbom-bluefin artifact (retention: 7 days)
  → promote-testing-to-main.yml (opens/updates auto/promote-testing-to-main PR)
  → merge queue (0 approvals required) → push to main
  → execute-release.yml fires on push to main
      execute:       reusable-execute-release.yml@v1  (re-tags :testing → :stable)
      release-notes: reusable-release.yml@v1          (downloads SBOM artifact + GitHub Release)
```

## Key workflows

| Workflow | What it does |
|---|---|
| `build-image-testing.yml` | Builds testing images; generates SBOM while layers are local; uploads `sbom-bluefin` and `image-digest-*` artifacts |
| `post-testing-e2e.yml` | Gates promotion on a passing e2e run against the testing digest |
| `promote-testing-to-main.yml` | Opens `auto/promote-testing-to-main` PR; 0 approvals, daily 04:00 UTC |
| `execute-release.yml` | Fires on push to `main`; promotes images, downloads build SBOM, creates GitHub Release |

## Execute-release jobs

`execute-release.yml` has three jobs:

1. **check-trigger** — passes only for promotion commits (`chore: promote testing to main`) or `workflow_dispatch`
2. **execute** — calls `reusable-execute-release.yml@v1`; cosign-verifies and re-tags images `:testing → :stable`
3. **release-notes** — calls `reusable-release.yml@v1`; downloads build-time SBOM artifact, renders release card, creates GitHub Release

## SBOM architecture — build time, not release time

**SBOM is generated during `reusable-build` while the image layers are already on disk.**
`reusable-release` then downloads the pre-built artifact — no image pull required.

```
reusable-build.yml
  └─ Generate SBOM (Syft, rpm-db-cataloger, layers local)
  └─ Upload artifact: sbom-bluefin (retention: 7 days)

reusable-release.yml (called by execute-release.yml)
  └─ Find latest successful build run for build_workflow + build_branch
  └─ Download artifact: sbom-bluefin from that run
  └─ create-release@v1: renders release card + GitHub Release
```

**Do NOT use `generate_sbom_inline: true`.** That re-pulls the full ~8 GB image from the registry
onto the release runner, which OOM-kills standard ubuntu-24.04 runners (exit 137 / exit 143).
Dakota has always used the artifact-download pattern; bluefin and bluefin-lts were corrected in
PR #730 / bluefin-lts #385.

### Correct execute-release.yml snippet

```yaml
release-notes:
  uses: projectbluefin/actions/.github/workflows/reusable-release.yml@v1
  with:
    build_workflow: build-image-testing.yml   # workflow that uploaded the SBOM
    build_branch: testing                     # branch to search for the build run
    sbom_artifact: sbom-bluefin               # artifact name from reusable-build
    stream_name: stable
    image: ghcr.io/projectbluefin/bluefin
    ...
```

| Repo | `sbom_artifact` | `build_workflow` |
|---|---|---|
| `bluefin` | `sbom-bluefin` | `build-image-testing.yml` |
| `bluefin-lts` | `sbom-bluefin-lts-hwe` | `build-regular-hwe.yml` |
| `dakota` | `sbom-dakota` | `publish.yml` (BST-native SBOM) |

## Re-triggering a failed release

If `release-notes` fails or the GitHub Release is missing/wrong:

```bash
# 1. Delete the broken release (keeps the git tag — do NOT use --cleanup-tag)
gh release delete <tag> --repo projectbluefin/bluefin --yes

# 2. Re-trigger via workflow_dispatch (check-trigger passes unconditionally)
gh workflow run execute-release.yml --repo projectbluefin/bluefin --ref main
```

**Idempotency trap:** `create-release` skips silently if the GitHub Release tag already exists.
Always delete the broken release before re-triggering.

**SBOM artifact expiry:** The `sbom-bluefin` artifact is retained for 7 days. If the release is
triggered more than 7 days after the build, the artifact will be missing. Re-trigger a new build
first, or accept the release with an empty SBOM.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `release-notes` OOM / exit 137 | `generate_sbom_inline: true` still set — re-pulls full image at release time | Remove `generate_sbom_inline: true`; add `build_workflow`, `build_branch`, `sbom_artifact` |
| `release-notes` fails: "Artifact not found: sbom-bluefin" | Build run artifact expired (>7 days) or build failed before SBOM step | Re-trigger a fresh build, then re-trigger release |
| Release exists but shows 0 packages | SBOM is a fallback stub (Syft OOM'd during build) | Re-trigger build; check `reusable-build` SBOM step logs |
| Release-notes job skipped | Re-triggered run's commit message didn't match pattern | Use `workflow_dispatch` — `check-trigger` passes unconditionally |
| Release card exists but no package table | `create-release` received an empty or invalid SBOM | Check SBOM artifact: `gh run download <run-id> -n sbom-bluefin` |

## Non-obvious patterns

- `execute-release.yml` trigger: `workflow_dispatch` always passes; push to `main` only passes if commit message matches `^chore: promote testing to main`
- `reusable-release.yml` computes tag as `stable-$(date -u +%Y%m%d)`. If a release with that tag already exists, `create-release` skips silently.
- The centralized `create-release@v1` renders the full release body: release card, key components table, full SPDX package inventory, supply chain verification. A `post-release-variants` job prepends the variants table.
- `bluefin-lts` uses `image: ghcr.io/projectbluefin/bluefin-lts-hwe` for release notes so the HWE kernel version appears in the key components table.
- SBOM artifact name = `sbom-${IMAGE_NAME}` where `IMAGE_NAME = just image_name <brand_name> <stream> <flavor>`. For main flavor: `sbom-bluefin`, `sbom-bluefin-lts-hwe`, `sbom-dakota`.
- **Check same-org repos before implementing any release pattern.** Dakota, bluefin-lts, and bluefin share the same reusables. If one repo solved it, copy the pattern exactly.

## Red Flags

- `generate_sbom_inline: true` anywhere in `execute-release.yml` — remove it immediately
- Release body has only a supply chain section with no package table — `release-notes` job failed
- `release-notes` job OOM (exit 137) — `generate_sbom_inline: true` still present
- Release shows "0 packages" — SBOM is a stub; check build run Syft step

## Verification

- [ ] `release-notes` job shows green in the Actions run
- [ ] GitHub Release tag exists with `release-card.png` and SBOM assets attached
- [ ] Release body includes "Key components" table and full package inventory
- [ ] Package count > 0 (a stub SBOM shows 0)

## When to use

- Promoting `:testing` builds to `:stable`
- Diagnosing why a release has missing SBOM or package information
- Re-triggering a failed or incomplete release
- Understanding the centralized release action in `projectbluefin/actions`

## When NOT to use

- Routine PR work → [build.md](build.md)
- Renovate dependency handling → [renovate.md](renovate.md)
- ISO release work → [iso.md](iso.md)
- LTS stream specifics → `projectbluefin/bluefin-lts` repo

## Current release flow

```text
PR merges to testing
  → build-image-testing.yml (Testing Images)
  → promote-testing-to-main.yml (opens/updates auto/promote-testing-to-main PR)
  → merge queue (0 approvals required) → push to main
  → execute-release.yml fires on push to main
      execute:       reusable-execute-release.yml@v1  (re-tags :testing → :stable)
      release-notes: reusable-release.yml@v1          (SBOM + GitHub Release)
```

## Key workflows

| Workflow | What it does |
|---|---|
| `build-image-testing.yml` | builds testing images; uploads `image-digest-*` artifacts |
| `post-testing-e2e.yml` | gates promotion on a passing e2e run against the testing digest |
| `promote-testing-to-main.yml` | opens `auto/promote-testing-to-main` PR; 0 approvals, daily 04:00 UTC |
| `execute-release.yml` | fires on push to `main`; promotes images and creates GitHub Release |

## Execute-release jobs

`execute-release.yml` has three jobs:

1. **check-trigger** — passes only for promotion commits (`chore: promote testing to main`) or `workflow_dispatch`
2. **execute** — calls `reusable-execute-release.yml@v1`; cosign-verifies and re-tags images `:testing → :stable`
3. **release-notes** — calls `reusable-release.yml@v1`; generates SBOM inline, renders release card, creates GitHub Release

## SBOM and package information

Release notes are generated by `projectbluefin/actions/bootc-build/create-release@v1`:

- Scans the promoted image with Syft (`--override-default-catalogers rpm-db-cataloger`) — RPM-only scan, fast, low memory
- Diffs against the previous release SBOM to show changed/added/removed packages
- Renders a release card PNG (light + dark)
- Creates the GitHub Release with the SBOM attached as `bluefin.spdx.json`

**Use `generate_sbom_inline: true` in `execute-release.yml`.** Syft scans `registry:IMAGE:stable` directly using only the RPM database cataloger. All notable packages (kernel, GNOME, Podman, systemd, Mesa, PipeWire, Flatpak, bootc) are RPMs. `GOMEMLIMIT=3GiB GOGC=25` cap the Go heap to prevent OOM on 7 GB runners.

## Re-triggering a failed release

If the `release-notes` job fails (runner shutdown, transient infrastructure):

```bash
# 1. If the GitHub Release was created with wrong/missing content, delete it
#    (keeps the git tag — do NOT use --cleanup-tag)
gh release delete <tag> --repo projectbluefin/bluefin --yes

# 2. Re-trigger execute-release via workflow_dispatch (reads from main branch)
gh workflow run execute-release.yml --repo projectbluefin/bluefin --ref main
```

**Idempotency trap:** `create-release` skips creation if the GitHub Release tag already exists. Always delete the broken release before re-triggering, or the SBOM and package info will never be written.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Release exists but shows 0 packages | Old code: `syft registry:` with 180s timeout fell back to empty stub | Fix is in `@v1` already (oci-dir approach); delete release and re-trigger |
| `release-notes` fails: "Artifact not found: sbom-bluefin" | `generate_sbom_inline: false` but artifact not in build run | Switch back to `generate_sbom_inline: true` in `execute-release.yml` |
| `release-notes` fails: runner received shutdown signal | Transient infrastructure kill during skopeo image pull (~5 min) | Delete release and re-trigger; usually succeeds on retry |
| Release-notes job skipped | Re-triggered run's commit message didn't match pattern | Use `workflow_dispatch` — `check-trigger` passes unconditionally |
| Release card exists but no package table | SBOM validation passed but `packages: []` in SBOM file | Syft format mismatch or empty OCI dir during scan |

## Non-obvious patterns

- `execute-release.yml` trigger: `workflow_dispatch` always passes; push to `main` only passes if commit message matches `^chore: promote testing to main`
- `reusable-release.yml` computes tag as `stable-$(date -u +%Y%m%d)`. If a release with that tag already exists (e.g. manually created), `create-release` skips creation silently.
- The centralized `create-release@v1` renders the full release body: release card, key components table, full SPDX package inventory, supply chain verification. A `post-release-variants` job prepends the variants table (present in both bluefin and bluefin-lts).
- bluefin-lts uses `image: ghcr.io/projectbluefin/bluefin-lts-hwe` for release notes so the HWE kernel version appears in the key components table.
- SBOM generation via `skopeo copy → oci-dir` takes 4–8 minutes for a full GNOME desktop image. Transient runner shutdowns are expected on spot instances; retry before investigating further.

## Red Flags

- Release body has only a "## Supply chain" section with no package table — release was manually created or `release-notes` job failed
- `generate_sbom_inline: false` in `execute-release.yml` without a verified `sbom-bluefin` artifact in the recent build run
- Release shows "0 packages" — SBOM is a stub (old timeout fallback or Syft JSON vs SPDX JSON mismatch)
- `release-notes` job was skipped — check `check-trigger`; the dispatch trigger might have been a non-promotion push

## Verification

- [ ] `release-notes` job shows green in the Actions run
- [ ] GitHub Release tag exists with `release-card.png` and `bluefin.spdx.json` assets attached
- [ ] Release body includes "Key components" table and full package inventory
- [ ] `total_packages` in the release body is > 0 (a stub SBOM shows 0)
