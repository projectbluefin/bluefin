# Bluefin LTS Variant

## When to use

- Working in `projectbluefin/bluefin-lts`
- Explaining how LTS differs from the main Bluefin repo
- Checking LTS promotion or ISO safety rules

## When NOT to use

- Normal work in this repo (`projectbluefin/bluefin`) → [build.md](build.md)
- General ISO guidance for stable/latest → [iso.md](iso.md)

## First rule

**Bluefin LTS lives in the `bluefin-lts` repo, not this repo.**

## Core differences

| Aspect | Bluefin | Bluefin LTS |
|---|---|---|
| Repo | `projectbluefin/bluefin` | `projectbluefin/bluefin-lts` |
| Base | Fedora | CentOS Stream |
| Primary stream model | testing/latest/stable | testing/lts promotion |
| Image names (post PR #73) | `bluefin` / `bluefin-nvidia-open` | `bluefin-lts` / `bluefin-lts-hwe` / `bluefin-gdx` |
| ISO status | active | non-HWE LTS ISO is disabled |

## Critical ISO warning

**Do not build or promote non-HWE LTS ISOs.**

Specifically:
- do not re-enable disabled LTS ISO schedules
- do not promote `variant: lts`
- do not treat `variant: all` as safe if it includes non-HWE LTS

## LTS promotion rules

- Land changes in `main` first (PRs target `main`, not `lts`)
- **Production promotion is digest-based** (pending [bluefin-lts#77](https://github.com/projectbluefin/bluefin-lts/issues/77)) — same model as bluefin and dakota: build once, gate e2e, skopeo copy `:testing` → `:lts`
- Current state: `scheduled-lts-release.yml` still rebuilds from source weekly; [bluefin-lts#77](https://github.com/projectbluefin/bluefin-lts/issues/77) will replace it with digest promotion + 7-day floor
- **Never use squash merge for `main` → `lts` promotion PRs** — use merge commit to preserve ancestry
- After promotion, the release workflow generates the GitHub release automatically

## Org-wide promotion pipeline (all three repos)

Target model per [common#516](https://github.com/projectbluefin/common/issues/516):

```
Build       → :$sha only
Gate        → e2e on :$sha@digest → skopeo copy → :testing
Promote     → weekly Tuesday 06:00 UTC
             → 7-day floor (bypass on workflow_dispatch)
             → lock :testing digest → e2e → cosign verify → skopeo copy → :lts/:stable/:latest
             → fast-forward branch → generate release
```

| Repo | Status |
|---|---|
| `bluefin` | ✅ complete |
| `dakota` | ✅ complete |
| `bluefin-lts` | ⏳ [bluefin-lts#77](https://github.com/projectbluefin/bluefin-lts/issues/77) — unblocked (PR #73 merged) |

## Useful checks

```bash
just check
```

Inspect published tags:
```bash
skopeo list-tags docker://ghcr.io/projectbluefin/bluefin
```

## Non-obvious patterns

- LTS guidance often looks similar to Bluefin guidance, but branch rules and publish behavior differ
- Broken LTS ISO output must not overwrite older known-good production artifacts
- If you are unsure whether a task belongs here or in the main repo, check the repo name first

## Lessons learned

<!-- Add reusable LTS patterns here -->
