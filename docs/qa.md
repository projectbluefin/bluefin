# Quality and validation

## Default gate

```bash
just check
pre-commit run --all-files
```

## Change matrix

| Changed area | Minimum focused validation |
|---|---|
| Markdown or agent instructions | link and metadata checks, then pre-commit |
| `build_files/` shell | `bash -n`, ShellCheck, relevant Bats tests |
| `tests/unit/` | `bats tests/unit/` |
| `Containerfile` or image inputs | default gate plus an image build when practical |
| GitHub Actions | workflow lint and the affected local command |
| Release or signing logic | focused workflow review and source-derived verification |

Do not run a cold full image build for documentation-only changes.

## Review requirements

Report commands exactly as run. Treat source files and workflow definitions as
the authority for expected behavior. Add regression coverage when a reusable
script behavior changes.
