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
| Primary stream model | testing/latest/stable | main/lts promotion |
| ISO status | active | non-HWE LTS ISO is disabled |

## Critical ISO warning

**Do not build or promote non-HWE LTS ISOs.**

Specifically:
- do not re-enable disabled LTS ISO schedules
- do not promote `variant: lts`
- do not treat `variant: all` as safe if it includes non-HWE LTS

## LTS promotion rules

- Land changes in `main` first
- Promotion from `main` to `lts` must preserve a clean merge base
- **Never use squash merge for promotion PRs**
- After promotion, run the release/publish workflow explicitly if required by that repo

Typical commands:
```bash
gh workflow run scheduled-lts-release.yml --repo projectbluefin/bluefin-lts
```

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
