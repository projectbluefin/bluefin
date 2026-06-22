# CI Reference

The authoritative CI documentation lives in [`docs/skills/ci.md`](skills/ci.md).

Load that file for:
- Full workflow map (all 24 workflows, triggers, and purposes)
- Promotion pipeline mental model
- Common failure modes and fixes
- Shared actions architecture (`projectbluefin/actions` reusables)
- Hard rules for agents

## Quick triage
```bash
gh run list --repo projectbluefin/bluefin --limit 20
gh run view RUN_ID --repo projectbluefin/bluefin --log-failed
gh run rerun RUN_ID --repo projectbluefin/bluefin --failed-only
```
