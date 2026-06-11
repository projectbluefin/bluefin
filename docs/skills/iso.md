# ISO Building and Promotion

## When to use

- Working with `projectbluefin/dakota-iso`
- Building or promoting installation ISOs
- Troubleshooting ISO promotion or prerelease behavior

## When NOT to use

- Changing image contents in this repo → [build.md](build.md)
- LTS variant repo guidance → [lts.md](lts.md)
- General GitHub Actions debugging outside ISO workflows → [ci.md](ci.md)

## First rule

**ISO building and promotion happens in the separate `projectbluefin/dakota-iso` repo/workflows.**

## Safety rules

- **Do not build or promote non-HWE LTS ISOs** unless there is an explicit, reviewed safety override
- Do not overwrite known-good production LTS ISO artifacts with broken output
- Treat `stable` and `lts-hwe` as the safe default variants

## High-level flow

```text
container image built in image repo
  -> bluefin-iso build workflow
  -> testing/prerelease artifacts
  -> promotion workflow copies testing -> production
```

## Useful commands

Build a stable ISO workflow manually:
```bash
gh workflow run build-iso-stable.yml --repo projectbluefin/dakota-iso
```

Promote a safe variant:
```bash
gh workflow run promote-iso.yml --repo projectbluefin/dakota-iso -f variant=stable
```

If applicable, generate or inspect release notes from the image repo first:
```bash
just changelogs stable
```

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| ISO workflow cannot find a source image | target image tag was not published | verify GHCR image/tag first |
| promotion should be safe but includes LTS | wrong variant selection | use `stable` or `lts-hwe`, not `all`/`lts` |
| prerelease/promotion missing assets | upstream build failed before artifact upload | inspect the originating ISO build run first |
| build script fails disabling a service | unit no longer exists and script is under `set -e` | remove or guard the disable call |

## Non-obvious patterns

- ISO issues are often downstream of image publication issues; verify the source image digest before debugging Anaconda/Titanoboa
- Promotion safety matters more than forcing a broken rebuild through
- Keep image-repo release logic and ISO-repo promotion logic mentally separate

## Lessons learned

<!-- Add reusable ISO patterns here -->
