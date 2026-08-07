# Workflow map

The workflow directory is authoritative. Keep any inventory here source-derived
and update it whenever a workflow is added, removed, renamed, or retargeted.

For current workflows:

```bash
find .github/workflows -maxdepth 1 -type f -name '*.yml' -o -name '*.yaml' | sort
git grep -n '^name:\|^on:' .github/workflows
```
