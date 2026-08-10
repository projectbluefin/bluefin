# MergeRaptor Checks permission for lab-check.yml

`actions/create-github-app-token` can only request permissions the app
installation already holds; anything else fails the run with `The permissions
requested are not granted to this installation.` The MergeRaptor installation
on `projectbluefin` therefore needs **Checks: write** for `lab-check.yml`, in
addition to the contents/pull-requests/workflows grants `track-common.yml`
uses.

Granting an app permission is org-admin administration in the GitHub UI, not a
repository change. Never work around a missing grant with a PAT.

## Two levels, and they fail identically

A GitHub App permission exists at two levels, and the token-mint error is the
same either way. Fixing the wrong one looks like doing nothing:

| Level | What it means | Where it is changed |
|---|---|---|
| **Declared** on the app | The app definition *asks* for the permission | Org settings → Developer settings → GitHub Apps → MergeRaptor → Permissions & events |
| **Granted** on the installation | An org owner *approved* what the app asked for | Org settings → GitHub Apps → MergeRaptor |

An installation can never be granted a permission the app does not declare.
When `checks` is missing from the app definition there is no pending request
for an owner to approve, so re-installing or re-approving the app accomplishes
nothing — the app has to ask first.

## Which level are you missing?

Both commands need org-owner (or app-owner) access; they 404 for everyone else,
which is itself not a diagnosis.

```bash
# What the app DECLARES
gh api /apps/mergeraptor --jq '{owner: .owner.login, permissions}'

# What the installation was GRANTED
gh api orgs/projectbluefin/installations \
  --jq '.installations[] | select(.app_slug == "mergeraptor") | .permissions'
```

- `checks` absent from **both** → start at step 1 below.
- `checks` in the declared set but not the granted set → only step 2 is left.
- `checks: write` in both → the permission is fine; look elsewhere.

## Fix, in order

1. **Declare it on the app.** Org settings → Developer settings → GitHub Apps →
   **MergeRaptor** → Permissions & events → Repository permissions →
   **Checks: Read and write**. Save. This raises a permission request to org
   owners.
2. **Approve it on the installation.** Org settings → GitHub Apps →
   **MergeRaptor** → review and accept the request.

Then re-run any Lab check, or dispatch a `lab-check` repository event, and
confirm `testing-lab / <product>` is created or updated.

## Do not paper over it

`lab-check.yml` mints the token with `continue-on-error: true` purely so the
next step can emit an actionable `::error::` instead of a bare red X; the job
still exits 1. Note that this makes the token step *report* conclusion
`success` while its `outcome` is `failure` — that is expected, and the
diagnostic keys off `outcome`. Do not add a fallback that skips the report or
downgrades the failure: a Lab check that silently passes is worse than one that
is loudly broken.
