# Quality and validation

The factory-wide QA coverage model is canonical in
[`common/docs/skills/qa.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/qa.md).
This document covers only what this repository runs.

## Default gate

```bash
just check
pre-commit run --all-files
```

`just check` validates Just syntax. `pre-commit` runs the hooks configured in
[`.pre-commit-config.yaml`](../.pre-commit-config.yaml): JSON/TOML/YAML checks,
whitespace and merge-conflict checks, private-key detection, `actionlint`,
ShellCheck over `build_files/` and `system_files/`, the documentation validator
[`.github/scripts/validate-docs.py`](../.github/scripts/validate-docs.py), and
the action-pinning guards.

## Change matrix

| Changed area | Minimum focused validation |
|---|---|
| Markdown or agent instructions | `python3 .github/scripts/validate-docs.py`, then pre-commit |
| `build_files/` or `system_files/` shell | `bash -n`, ShellCheck, relevant Bats tests |
| `tests/unit/` | `just test-unit` (wraps `bats tests/unit/`) |
| `tests/*.py` | `python3 -m unittest discover -s tests -p 'test_*.py'` |
| `Containerfile` or image inputs | default gate plus an image build when practical |
| GitHub Actions | `actionlint` via pre-commit and the affected local command |
| Release or signing logic | focused workflow review and source-derived verification |

Do not run a cold full image build for documentation-only changes.

## CI gates

- [`pr-validation.yml`](../.github/workflows/pr-validation.yml) — rejects pull
  requests based on `main`, blocks undeclared gitlinks, runs the shared
  `validate-pr` action, runs the Bats suite with kcov coverage and the Python
  unit tests, and runs the `smoke` end-to-end suite on `merge_group` only.
- [`build-image-testing.yml`](../.github/workflows/build-image-testing.yml) —
  builds and publishes images; documentation and Markdown paths are ignored.
- [`post-testing-e2e.yml`](../.github/workflows/post-testing-e2e.yml) — runs
  `smoke,common` against the digest built from `testing`.
- [`nightly.yml`](../.github/workflows/nightly.yml) — runs
  `smoke,common,vanilla-gnome` against `:testing` at 02:00 UTC.

End-to-end suites are executed through
[`run-testsuite.yml`](../.github/workflows/run-testsuite.yml); never call the
`projectbluefin/testsuite` workflow directly.

## Review requirements

Report commands exactly as run. Treat source files and workflow definitions as
the authority for expected behavior. Add regression coverage in `tests/unit/`
when a reusable script behavior changes.
