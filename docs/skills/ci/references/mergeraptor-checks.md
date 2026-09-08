# MergeRaptor Checks permission for lab-check.yml

`actions/create-github-app-token` can only request permissions the app
installation already holds; anything else fails the run with `The permissions
requested are not granted to this installation.` The MergeRaptor installation
on `projectbluefin` therefore needs **Checks: write** for `lab-check.yml`, in
addition to the contents/pull-requests/workflows grants `track-common.yml`
uses.

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

| `checks` in App permissions | `checks` in installation permissions | What it means |
|---|---|---|
| absent | absent | The App cannot request it yet. **Both steps below are required.** Re-installing or re-approving does nothing — there is no pending request to approve. |
| present | absent | Only step 2 — an org owner approves the pending permission request. |
| present | `write` | Grant is in place; `lab-check.yml` should mint its token. Investigate elsewhere. |

## The fix (UI only — there is no REST endpoint for this)

**Step 1 — declare it on the App.** Organization settings → Developer settings →
GitHub Apps → **MergeRaptor** → Permissions & events → Repository permissions →
**Checks: Read and write** → Save. Skipping this is the common failure: it is a
*different screen* from the installation page, and until it is done the
installation page offers nothing to approve.

**Step 2 — approve it on the installation.** Saving step 1 raises a permission
request to org owners. Accept it under Organization settings → GitHub Apps →
MergeRaptor → **Review request**.

Then re-run the check with the step-2 command above; `checks` must read `write`.
Dispatch a `lab-check` repository event (or wait for the next `track-common` QA
run) and confirm `testing-lab / <product>` is created or updated.

## Rules

Granting an app permission is org-admin administration in the GitHub UI, not a
repository change. Never work around a missing grant with a PAT, and never add a
fallback that lets `lab-check.yml` pass without reporting: a check that silently
skips is worse than one that fails loudly, because the gap stops being visible.
`lab-check.yml` requests exactly `permission-checks: write` and
`permission-contents: read`, which is the minimum the check-run API needs.

## Reading a failed run

The job summary shows **`Get MergeRaptor token: success`** directly above a
failing diagnostic step. That is not a second bug and the mint did not
half-succeed. `continue-on-error: true` makes a step report *conclusion*
`success` while its *outcome* stays `failure`; the diagnostic keys off
`outcome`, which is correct. Confirm the real result in the step log — a denied
mint logs `##[error]The permissions requested are not granted to this
installation` and an HTTP `422` from
`POST /app/installations/{id}/access_tokens`.
