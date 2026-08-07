# CI failure triage

| Symptom | First check |
|---|---|
| No checks | Pull request base branch and path filters |
| Validation differs locally | Run `just check` and `pre-commit run --all-files` |
| Workflow did not trigger | Event, branch, and path filters in the YAML |
| Promotion is blocked | Exact digest, required check, and merge-group state |
| Shared action behaves incorrectly | Reusable workflow source and its callers |
| Tests update but E2E setup stays stale | Compare the reusable workflow `uses` ref with its test checkout ref |

Always inspect the failed run logs before changing a workflow.

A reusable testsuite workflow has two independent refs: `uses` selects the
workflow definition and `test_ref` selects the test tree it checks out. A
managed `test_ref` does not deliver workflow-level fixes such as VM disk sizing
when `uses` is pinned to an older commit. Keep both layers on the documented
managed ref, and verify the nested workflow shown in the run log.
