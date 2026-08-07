# Contribution workflow

## Work states

**Trust the Machines: workflows own state; humans provide intent.**

The factory uses exactly seven canonical workflow labels: `1-triage`,
`2-discussing`, `3-human-queue`, `3-clanker-queue`, `4-review`, `blocked`, and
`hold`. Their meanings, ownership, and the full lifecycle are canonical in
[`common/docs/skills/label-workflow.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
The names are listed here only so they are searchable; if anything here
disagrees with `common`, `common` wins and this file is the bug.

Automation applies and repairs these labels. Agents do not claim work with slash
commands, do not add or remove workflow labels, and do not manufacture queue
state. Never infer state from a stale label, an issue comment, or an unlinked
branch; read the current assignment, project state, branch, and pull request.

Repository-local labels (`kind/`, `area/`, `priority/`, `release/`) are
descriptive metadata, not workflow states. Confirm counts from `ujust report`
are evidence for a human priority call, not a label transition. `cherry-pick` is
an action trigger consumed by
[`cherry-pick-to-stable.yml`](../.github/workflows/cherry-pick-to-stable.yml),
not a state either.

## Finding work

```bash
gh search issues --label "3-clanker-queue" --owner projectbluefin --state open
```

Work only an issue routed to you by assignment, project state, or
`3-clanker-queue`. If blocked, describe the exact decision or dependency in the
issue and stop.

## Safe change flow

1. Identify the source-of-truth files.
2. Select the smallest matching skill.
3. Make one focused change.
4. Run the relevant validation.
5. Update the matching documentation when a reusable fact changes.
6. Open a pull request targeting `testing` containing `Closes #NNN`; normal
   feature work must not target `main`. `pr-validation.yml` fails a pull request
   based on `main`.

Do not self-approve or self-merge. Automation applies `4-review`; a human
reviews. Promotion of `testing` to `main` is automated — see
[`release.md`](release.md).

## Comment policy

- One comment per issue or pull-request event, at most; combine findings.
- Never duplicate GitHub UI state such as approvals or check runs.
- Test reports state what ran, pass/fail, and blockers only.
- Use `@` mentions only when asking for a specific action.
- If nothing actionable needs saying, post nothing.

## Documentation changes

Documentation-only changes still use the normal review path.
[`build-image-testing.yml`](../.github/workflows/build-image-testing.yml)
ignores `**.md`, so Markdown-only changes do not trigger an image build.

## Boundaries

Do not bypass review, signing, branch, or verification protections merely to
make a workflow appear green. Escalate a blocked trust or policy gate with the
relevant run and source path.

Report a factory gap by filing an issue in `projectbluefin/common`. Do not
self-apply a queue label — triage and queue admission are human decisions.
