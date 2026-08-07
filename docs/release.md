# Release model

Release behavior is defined by the workflow files under `.github/workflows/`
and by the reusable workflows they call in `projectbluefin/actions`. Read the
affected workflow before changing this document.

## Pipeline shape

The factory is automated end-to-end. The cross-repo contract is canonical in
[`common/docs/factory/agentic-model.md`](https://github.com/projectbluefin/common/blob/main/docs/factory/agentic-model.md)
("What autonomous means for promotions") and
[`common/docs/skills/release-promotion.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/release-promotion.md).
In this repository it is implemented by:

| Stage | Workflow | Trigger |
|---|---|---|
| Build and publish `:testing` | [`build-image-testing.yml`](../.github/workflows/build-image-testing.yml) | push to `main`/`testing`, `merge_group`, dispatch |
| End-to-end gate on `:testing` | [`post-testing-e2e.yml`](../.github/workflows/post-testing-e2e.yml) | successful `Testing Images` push run |
| Squash promotion PR | [`promote-testing-to-main.yml`](../.github/workflows/promote-testing-to-main.yml) | push to `testing` and `cron: 0 4 * * *` |
| `:testing` → `:stable` release | [`execute-release.yml`](../.github/workflows/execute-release.yml) | push to `main` with a promotion commit |
| Keep `testing` current | [`sync-main-to-testing.yml`](../.github/workflows/sync-main-to-testing.yml) | push to `main` |

Promotion opens or refreshes the `auto/promote-testing-to-main` pull request and
enqueues it in the `main` merge queue; the queue merges it once required checks
pass. Daily promotion is scheduled at 04:00 UTC and is a no-op when `testing`
matches `main`. An open promotion pull request is normal — it is not a fault.

`execute-release.yml` only acts on a promotion commit (`chore: promote testing
to main`) or an explicit dispatch. It copies the published `:testing` digest to
`:stable` for each variant and then generates release notes.

## Release trust

A release must preserve:

- verified image inputs
- reproducible build inputs where practical
- signature verification
- end-to-end validation before promotion
- release metadata and SBOM provenance

Release consumes `:testing` as its input rather than rebuilding, so the gate on
`:testing` is the functional gate for everything that reaches `:stable`.

## Agent procedure

For release or promotion work:

1. Load [`skills/release-artifacts/SKILL.md`](skills/release-artifacts/SKILL.md).
2. Read the relevant workflow and its inputs.
3. Check the exact image digest and artifact names.
4. Run the documented verification command.
5. Report failures without bypassing a trust gate.

Do not infer tags, triggers, variants, artifact names, or signing behavior from
memory. Read the workflow inputs — the published variant list lives in the
`variants` input of the promotion and release workflows.
