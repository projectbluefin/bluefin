# Renovate PR Handling

## When to use

- Reviewing or merging a Renovate or mergeraptor dependency PR
- Updating `.github/renovate.json5`
- Figuring out why Renovate did not open or merge a PR
- Triggering a central Renovate run

## When NOT to use

- Manual dependency bumps that Renovate should own
- Generic CI debugging outside Renovate behavior → [ci.md](ci.md)
- Package placement decisions → [packages.md](packages.md)

## Hard rules

- **No PATs.** Project Bluefin uses GitHub App auth with `RENOVATE_APP_ID` + `RENOVATE_PRIVATE_KEY`.
- **Never add `RENOVATE_TOKEN` or other PAT secrets.**
- **Renovate PRs should target `testing`, not `main`.**
- **Automerge logic must accept mergeraptor:**
  ```jq
  .author.login == "renovate[bot]" or .author.login == "app/mergeraptor"
  ```

## Trigger Renovate centrally

```bash
gh workflow run "Renovate Self-Hosted" --repo projectbluefin/renovate-config
```

Individual repos do not need their own self-hosted Renovate workflow.

## Local validation before committing config changes

```bash
npx --yes --package renovate -- renovate-config-validator --strict
```

Do this for changes to:
- `.github/renovate.json5`
- inherited/shared Renovate config files

## Base branch rules

Authoritative setting in this repo:
```json5
"baseBranchPatterns": ["testing"]
```

If a Renovate PR targets the wrong branch:
1. fix `.github/renovate.json5`
2. retrigger Renovate
3. correct or replace the already-open PRs

## Review and merge flow

```bash
gh pr list --repo projectbluefin/bluefin --author 'app/renovate'
gh pr view PR_NUMBER --repo projectbluefin/bluefin
gh pr review PR_NUMBER --repo projectbluefin/bluefin --approve
gh pr merge PR_NUMBER --repo projectbluefin/bluefin --squash
```

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Renovate PRs target `main` | wrong `baseBranchPatterns` | set branch pattern to `testing` |
| automerge skipped a passing PR | PR finder ignored `app/mergeraptor` | include both Renovate and mergeraptor authors |
| validator rejects config | stale field name | check current Renovate schema and rename the field |
| workflow asks for a PAT | wrong auth model | use GitHub App secrets, never PATs |

## Non-obvious patterns

- `config:best-practices` already covers GitHub Actions pin updates; do not add duplicate managers without a strong reason
- Unversioned `renovate` in the validator command is intentional: it validates against the current schema
- Passing a filename to `renovate-config-validator` can change how the file is interpreted; prefer repo auto-discovery unless you intentionally need another mode

## Shared actions version management

When `projectbluefin/actions` is live, Renovate will track action versions automatically via the `github-actions` manager. The contract:

- Actions are pinned to semver tags: `@v1`, `@v1.2.0`
- Renovate opens PRs when new versions are published
- Major version bumps (`v1` → `v2`) require manual review (breaking changes)
- Patch/minor bumps follow normal automerge rules

No additional Renovate config is needed beyond `config:best-practices` — it already covers `github-actions` pin updates.

## Lessons learned

<!-- Add reusable Renovate patterns here -->
