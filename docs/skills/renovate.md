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

## Automerge for Renovate/mergeraptor PRs

All Renovate and mergeraptor PRs automerge once `PR Validation — testsuite` passes:
- No manual review needed for digest/pin/patch/minor bumps (configured in `renovate.json`)
- `renovate-automerge.yml` runs `gh pr merge --auto --squash` — no high-risk/smoke distinction
- Requires: `testing` branch protection with `validate` as required check + `allow_auto_merge=true` at repo level

If auto-merge does not trigger:
1. Confirm `testing` has branch protection: `gh api repos/projectbluefin/bluefin/branches/testing/protection`
2. Confirm `allow_auto_merge` is set: `gh api repos/projectbluefin/bluefin --jq .allow_auto_merge`
3. Re-run the failed `PR Validation` check to re-trigger the `workflow_run` event

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Renovate PRs target `main` | wrong `baseBranchPatterns` | set branch pattern to `testing` |
| automerge skipped a passing PR | `testing` has no branch protection, or PR finder missed `app/mergeraptor` | enable branch protection on `testing` with `validate` required check; include both authors |
| `enablePullRequestAutoMerge` GraphQL error | repo `allow_auto_merge` not set | `gh api --method PATCH repos/projectbluefin/bluefin -f allow_auto_merge=true` |
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

- **`testing` has branch protection** — required check: `validate`; `allow_auto_merge=true` at repo level. `gh pr merge --auto --squash` works.
- **Bulk-merging chore PRs** — iterate with `gh pr merge NNN --repo projectbluefin/bluefin --squash`. Skip DIRTY ones (conflicts) and trigger Renovate to rebase them.
- **Conflicted Renovate PRs** — do not rebase by hand. Post `@renovate rebase` on the PR or trigger the central Renovate run and it will rebase all conflicting PRs automatically within a few minutes.
- **Wrong base branch** — Renovate PRs that land on `main` are not validated and cannot be enqueued. Retarget with `gh pr edit NNN --base testing`, then merge normally.
