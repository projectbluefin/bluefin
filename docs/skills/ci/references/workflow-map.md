# Workflow map

The workflow directory is authoritative. Keep any inventory here source-derived
and update it whenever a workflow is added, removed, renamed, or retargeted.

For current workflows:

```bash
find .github/workflows -maxdepth 1 -type f -name '*.yml' -o -name '*.yaml' | sort
git grep -n '^name:\|^on:' .github/workflows
```

## The testsuite reference contract

`.github/workflows/run-testsuite.yml` is the only workflow that may reference
`projectbluefin/testsuite/.github/workflows/e2e.yml` directly. Every other
caller goes through that wrapper, so the ref and `test_ref` are set in exactly
one place.

Two invariants, both enforced by `scripts/check-testsuite-workflow-ref.py` in
the `validate` job:

- the reference is `@v1` — testsuite advances that tag after each successful
  main-branch merge, so a digest pin silently freezes the gate on a stale test
  tree (this is the #929 regression);
- the wrapper passes `test_ref: v1`.

Renovate would otherwise undo the first one: `config:best-practices` pins
action refs to digests, so `projectbluefin/testsuite` is excluded from the
`github-actions` manager in `.github/renovate.json5`. Removing that exclusion
re-pins the ref and reintroduces the same freeze.

```bash
python3 scripts/check-testsuite-workflow-ref.py
```
