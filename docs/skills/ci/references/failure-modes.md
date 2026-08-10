# CI failure triage

| Symptom | First check |
|---|---|
| No checks | Pull request base branch and path filters |
| Validation differs locally | Run `just check` and `pre-commit run --all-files` |
| Workflow did not trigger | Event, branch, and path filters in the YAML |
| Promotion is blocked | Exact digest, required check, and merge-group state |
| Shared action behaves incorrectly | Reusable workflow source and its callers |

Always inspect the failed run logs before changing a workflow.

## Reading a failed `post-testing-e2e` run

`promote-to-testing` in `.github/workflows/post-testing-e2e.yml` needs
`run-e2e.result == 'success'`, so a single failing matrix leg makes the whole
gate `skipped`. Identify the failing leg and its failing scenarios before
concluding anything about the image:

```bash
gh run view RUN_ID --repo projectbluefin/bluefin --json jobs \
  --jq '.jobs[] | [.name, .conclusion] | @tsv'
gh run view RUN_ID --repo projectbluefin/bluefin --log \
  | grep -A20 'Failing scenarios:'
```

The behave summary line (`N scenarios passed, N failed`) and the
`Failing scenarios:` block name the exact feature file and line. That is the
only evidence that identifies the failure; job names do not.

## `cap_net_raw` missing on `/usr/bin/ping` is not an image regression

`system_health.feature` "composefs preserves file capabilities on newuidmap,
newgidmap, and ping" fails deterministically on smoke-b with:

```
composefs file-capability regression — missing capabilities:
  ["/usr/bin/ping: expected 'cap_net_raw' in ''"]
```

This has been triaged twice as a possible bluefin image-content defect. It is
not one. Fedora's `iputils` deliberately ships `ping` with **no file
capabilities** — it relies on unprivileged ICMP sockets via
`net.ipv4.ping_group_range`, which systemd sets by default. Only two binaries
in that package carry capabilities (`iputils.spec`, `f44`):

```spec
%attr(0755,root,root) %caps(cap_net_raw=p) %{_bindir}/clockdiff
%attr(0755,root,root) %caps(cap_net_raw=p) %{_bindir}/arping
%attr(0755,root,root) %{_bindir}/ping
```

There is no xattr on `ping` to preserve or strip, so the assertion cannot pass
on any Fedora-based image regardless of what composefs does.

The same failure proves composefs is working. The other two binaries in the
assertion do carry capabilities — `shadow-utils` sets `cap_setuid=ep` on
`newuidmap` and `cap_setgid=ep` on `newgidmap` — and both pass. Capability
preservation is fine; the expectation list is wrong.

Do not "fix" this by adding `setcap cap_net_raw` to `ping` in the image. That
diverges from Fedora for no functional gain — `ping` already works. The fix is
in `projectbluefin/testsuite`: drop `ping` from the assertion, or better, swap
it for `arping` or `clockdiff`, which genuinely carry `cap_net_raw=p` and so
make the scenario a real composefs test rather than a vacuous one.

## The `oras` screenshot error is not the failure

In `projectbluefin/testsuite`'s `e2e.yml@v1`, the `Push desktop screenshot to
GHCR` step builds a tag with
`IMAGE_SLUG=$(echo "${IMAGE}" | sed 's|ghcr.io/[^/]*/||' | tr ':' '-')`.
When the caller passes a digest reference — `post-testing-e2e.yml` passes
`ghcr.io/<owner>/bluefin@sha256:…` — the slug keeps the `@sha256-…` suffix and
`oras push` rejects it:

```
invalid reference: invalid digest "sha256-…"
```

That step is `continue-on-error: true`, so it produces a red `##[error]` line in
the log without failing the job. Runs that pass `:testing` by tag (for example
`nightly.yml`) do not show it at all. Do not report it as the cause of a
`post-testing-e2e` failure; find the behave summary instead.
