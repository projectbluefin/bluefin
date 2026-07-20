---
name: dependency-automation
description: Review dependency automation, Renovate configuration, and automated updates.
metadata:
  source-of-truth:
    - renovate.json
    - .github/renovate.json5
    - .github/workflows/renovate-automerge.yml
---

# Dependency automation

## Procedure

1. Read the repository configuration and the affected workflow.
2. Validate configuration changes with the repository's configured validator.
3. Preserve the configured authentication model; never add personal access
   tokens or credentials.
4. Confirm the pull request targets the development branch.
5. Run the default gate.

```bash
just check
pre-commit run --all-files
```

Do not document an automation rule until it is present in source configuration.
