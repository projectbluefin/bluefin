# MergeRaptor Checks permission for lab-check.yml

`actions/create-github-app-token` can only request permissions the app
installation already holds; anything else fails the run with `The permissions
requested are not granted to this installation.` The MergeRaptor installation
on `projectbluefin` therefore needs **Checks: write** for `lab-check.yml`, in
addition to the contents/pull-requests/workflows grants `track-common.yml`
uses. Confirm the current grants before debugging the workflow YAML:

```bash
gh api orgs/projectbluefin/installations \
  --jq '.installations[] | select(.app_slug == "mergeraptor") | .permissions'
```

Granting an app permission is org-admin administration in the GitHub UI, not a
repository change. Never work around a missing grant with a PAT.
