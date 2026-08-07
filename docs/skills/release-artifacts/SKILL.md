---
name: release-artifacts
version: "1.1"
last_updated: 2026-08-07
id: release-artifacts
one_line_purpose: Prepare, verify, and troubleshoot image release and promotion.
entry_point: docs/skills/release-artifacts/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [release, promotion, signing, verification]
description: >-
  Covers the testing-to-main promotion and release workflows, digest and tag
  verification, and signing gates. Use when running a release or diagnosing a
  failed promotion.
metadata:
  type: runbook
  source-of-truth:
    - .github/workflows/build-image-testing.yml
    - .github/workflows/post-testing-e2e.yml
    - .github/workflows/promote-testing-to-main.yml
    - .github/workflows/execute-release.yml
    - docs/release.md
---

# Release artifacts

## When to Use

- Running or diagnosing a release, promotion, or stream-tag advance.
- Tracing which digest a published tag points at, and which gate admitted it.

## Do not use when

- Making a local build-only change: use [build](../build/SKILL.md).
- Choosing an image, stream, or flavor: use [variants](../variants/SKILL.md).

## The promotion chain

Every workflow below is a thin caller; the logic lives in
`projectbluefin/actions`. Read the caller inputs, not remembered behavior.

1. **Build** — `build-image-testing.yml` (`name: Testing Images`) builds flavors
   `main` and `nvidia` on pushes to `main` and `testing`. It passes
   `publish_stream_tag: "false"`, so the build never publishes `:testing`
   itself; it emits `image-digest-testing-*` artifacts.
2. **Gate** — `post-testing-e2e.yml` runs `run-testsuite.yml` with
   `suites: smoke,common` against the built digest, then its
   `promote-to-testing` job `skopeo copy`s the verified digests to `:testing`.
   That job is guarded by `workflow_run.head_branch == 'main'`.
3. **Promote source** — `promote-testing-to-main.yml` calls
   `reusable-promote-squash.yml@v1` with `run_e2e: false` and
   `use_merge_queue: true`, rebuilding the `auto/promote-testing-to-main`
   branch fresh on every run. `sync-main-to-testing.yml` merges main back.
4. **Release** — `execute-release.yml` runs on pushes to `main` whose commit
   message starts with `chore: promote testing to main`, or on
   `workflow_dispatch`. It promotes `bluefin` and `bluefin-nvidia` from
   `source_tag: testing` to `target_tag: stable` in `ghcr.io/projectbluefin`,
   with `run_release_gate: true` and `gate_suites: smoke,common`.

## Procedure

1. Read the affected workflow and its reusable-workflow inputs.
2. Verify the exact image digest, tag, artifact name, and trigger.
3. Confirm signing and gate jobs reported explicit success.
4. Never bypass a failed trust or verification gate.
5. Report the run ID and the exact verification commands.

```bash
gh run list --repo projectbluefin/bluefin --workflow execute-release.yml --limit 20
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
```

## Verify a stream tag against its gate

A stream tag (`:testing`, `:stable`) is a claim that a digest passed its gate.
Resolve what the tag points at, then confirm that digest actually passed.

```bash
skopeo inspect --no-tags docker://ghcr.io/projectbluefin/bluefin:testing --format '{{.Digest}}'
gh run list --repo projectbluefin/bluefin --workflow post-testing-e2e.yml --limit 20
```

A promotion job reported as `skipped` while the stream tag still advanced means
something outside the gate is publishing it. Build-time tag computation is the
usual source: `just generate-build-tags` puts the bare stream tag in
`BUILD_TAGS`, so excluding it from a conditional does not remove it from the
push list. Filter the stream tag out of the list itself — this repository does
so by passing `publish_stream_tag: "false"` to the reusable build.

Never re-point or delete a published stream tag to "repair" this. That is
user-visible and belongs to a human.

`:stable` inherits everything `:testing` admitted, because release resolves the
digest behind `:testing` rather than rebuilding it. The release gate re-runs
`smoke,common` only; the `lifecycle` suite is currently disabled in
`post-testing-e2e.yml` (TODO #400). Treat only an explicit success as a pass; a
`skipped` gate step is never a pass.

## Red Flags

- Describing release behavior without reading the current workflow caller.
- Trusting a stream tag as evidence of promotion without resolving its digest.
- A promotion job that has never succeeded, yet its stream tag keeps advancing.
- Assuming a tag is updated before its promotion workflow completes.
- Re-triggering an existing release without checking idempotency.

## Verification

- [ ] `gh run view RUN_ID --repo projectbluefin/bluefin` shows the gate job as
      `success`, not `skipped`.
- [ ] `skopeo inspect --no-tags docker://ghcr.io/projectbluefin/bluefin:stable
      --format '{{.Digest}}'` matches the digest the release run promoted.
- [ ] `python3 .github/scripts/validate-docs.py` and `just check` pass.
