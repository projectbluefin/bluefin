# Release model

Release behavior is defined by the workflow files under `.github/workflows/`
and by the reusable workflows they call. Read the affected workflow before
changing this document.

## Release trust

A release must preserve:

- verified image inputs
- reproducible build inputs where practical
- signature verification
- end-to-end validation before promotion
- release metadata and SBOM provenance

## Agent procedure

For release or promotion work:

1. Load [`skills/release-artifacts/SKILL.md`](skills/release-artifacts/SKILL.md).
2. Read the relevant workflow and its inputs.
3. Check the exact image digest and artifact names.
4. Run the documented verification command.
5. Report failures without bypassing a trust gate.

Do not infer tags, triggers, artifact names, or signing behavior from memory.
