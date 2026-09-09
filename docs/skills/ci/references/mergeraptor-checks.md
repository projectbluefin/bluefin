# MergeRaptor and lab-check.yml authentication

`lab-check.yml` creates and updates the `testing-lab / <product>` Check Run
with the workflow's own `GITHUB_TOKEN`, declaring `checks: write` in the
workflow `permissions:` block. It no longer mints a MergeRaptor app token:
`actions/create-github-app-token` can only request permissions the app
installation already holds, and the `projectbluefin` installation was never
granted **Checks: write**, so every dispatch died with HTTP `422` `The
permissions requested are not granted to this installation` (bluefin#939,
bluefin#1114). Requesting only permissions the installation already holds —
here, via the workflow token — is the fix that needs no org administration.

The check-run lookup matches by name only, with a server-side `check_name`
filter. A run created with `GITHUB_TOKEN` is attributed to the
`github-actions` app, so filtering on the requesting app's slug would find
nothing and every lifecycle event would POST a duplicate run (bluefin#1114).

`track-common.yml` and `renovate-automerge.yml` still mint MergeRaptor
installation tokens, but request only the contents and pull-requests
permissions the installation already holds. If one of them starts failing
with the `422` message above, a grant changed — confirm the current grants
before debugging the workflow YAML:

```bash
gh api orgs/projectbluefin/installations \
  --jq '.installations[] | select(.app_slug == "mergeraptor") | .permissions'
```

## Diagnose before fixing: App definition vs. installation

A permission lives at two levels, and the same error message covers both. Check
both before touching anything — the fix differs, and the installation-level fix
is a dead end when the App itself has not declared the permission.

**1. What the App declares** — the menu of permissions it is allowed to ask for:

```bash
gh api /apps/mergeraptor --jq '{owner: .owner.login, permissions}'
```

**2. What this org's installation grants** — what it actually holds:

```bash
gh api orgs/projectbluefin/installations \
  --jq '.installations[] | select(.app_slug == "mergeraptor") | .permissions'
```

Both commands need an org-owner token (`admin:org`); a contributor token returns
`404`/`Not Found`, which is not evidence either way.

Read the two together:

| Permission in App permissions | Permission in installation permissions | What it means |
|---|---|---|
| absent | absent | The App cannot request it yet. **Both steps below are required.** Re-installing or re-approving does nothing — there is no pending request to approve. |
| present | absent | Only step 2 — an org owner approves the pending permission request. |
| present | `write` | Grant is in place; the workflow should mint its token. Investigate elsewhere. |

## The fix (UI only — there is no REST endpoint for this)

**Step 1 — declare it on the App.** Organization settings → Developer settings →
GitHub Apps → **MergeRaptor** → Permissions & events → Repository permissions →
the permission in question (for example **Checks: Read and write**) → Save.
Skipping this is the common failure: it is a *different screen* from the
installation page, and until it is done the installation page offers nothing to
approve.

**Step 2 — approve it on the installation.** Saving step 1 raises a permission
request to org owners. Accept it under Organization settings → GitHub Apps →
MergeRaptor → **Review request**.

Then re-run the step-2 command above and dispatch the affected workflow to
confirm the token mint succeeds.

## Rules

Granting an app permission is org-admin administration in the GitHub UI, not a
repository change. Never work around a missing grant with a PAT, and never add
a fallback that lets a reporting workflow pass without reporting: a check that
silently skips is worse than one that fails loudly, because the gap stops being
visible.

## Reading a failed run

When `actions/create-github-app-token` requests a permission the installation
lacks, the step fails with the annotation `The permissions requested are not
granted to this installation` (an HTTP `422` from
`POST /app/installations/{id}/access_tokens`) and nothing else. With
`continue-on-error: true` the step reports *conclusion* `success` while its
*outcome* stays `failure`; key any diagnosis off `outcome`, and confirm the
denied mint in the step log.
