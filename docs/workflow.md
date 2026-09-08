# Contribution workflow

## Work states

**Trust the Machines: workflows own state; humans provide intent.**

The factory uses exactly seven canonical labels. The contract is canonical in
[`common/docs/skills/label-workflow.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md);
this list exists only so the names are searchable here. If it ever disagrees
with `common`, `common` wins and this table is the bug.

| Label | Meaning |
|---|---|
| `1-triage` | New work awaiting triage |
| `2-discussing` | Discussion or design clarification |
| `3-human-queue` | Admitted to the human-maintained queue |
| `3-clanker-queue` | Admitted to the agent-maintained queue |
| `4-review` | Pull request awaiting review |
| `blocked` | Waiting on human input or an external dependency |
| `hold` | Intentionally paused |

Automation applies and repairs these labels. Agents do not claim work with slash
commands, do not add or remove workflow labels, and do not manufacture queue
state. Never infer state from a stale label, an issue comment, or an unlinked
branch; read the current assignment, project state, branch, and pull request.

Repository-local labels (`kind/`, `area/`, `priority/`, `release/`) are
descriptive metadata, not workflow states. Confirm counts from `ujust report`
are evidence for a human priority call, not a label transition.

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
   feature work must not target `main`. That keyword only auto-closes the
   issue once the commit reaches the default branch `main` — see
   [issue-lifecycle](skills/issue-lifecycle/SKILL.md) — so the issue stays
   open through the `testing` merge until `promote-testing-to-main.yml` runs.

Do not self-approve or self-merge. Automation applies `4-review`; a human
reviews.

## Comment policy

- One comment per issue or pull-request event, at most; combine findings.
- Never duplicate GitHub UI state such as approvals or check runs.
- Test reports state what ran, pass/fail, and blockers only.
- Use `@` mentions only when asking for a specific action.
- If nothing actionable needs saying, post nothing.

## Documentation changes

Documentation-only changes still use the normal review path. They should not
trigger expensive image builds unless a workflow path filter says otherwise.

## Boundaries

Do not bypass review, signing, branch, or verification protections merely to
make a workflow appear green. Escalate a blocked trust or policy gate with the
relevant run and source path.

Report a factory gap by filing an issue in `projectbluefin/common`. Do not
self-apply a queue label — triage and queue admission are human decisions.
