# AGENTS.md

Bluefin is [`projectbluefin/bluefin`](https://github.com/projectbluefin/bluefin): a Containerfile-driven rpm-ostree GNOME desktop image.

**Read [`docs/SKILL.md`](docs/SKILL.md) before doing any work.** Load only the docs that match the task.

## Docs router

- [`docs/SKILL.md`](docs/SKILL.md) — task router
- [`docs/workflow.md`](docs/workflow.md) — issue lifecycle, bonedigger, labels, PR policy
- [`docs/pr-checklist.md`](docs/pr-checklist.md) — PR gates by change type
- [`docs/build.md`](docs/build.md) — build model and local validation loop
- [`docs/ci.md`](docs/ci.md) — CI, promotion, and failure modes

## Org pipeline — projectbluefin

### Repo map

```text
common ──────────────────────────┐
(shared OCI layer)               │
                                 ▼
bluefin  (PRs→testing; testing→main via promotion PR; main→:stable on release)
bluefin-lts (PRs→testing*; testing→main; main→lts on release)
dakota  (PRs→testing; testing→main via promotion PR; main→:stable on release)
                                 │
                                 ▼
                                iso (installation media)
```

(*) bluefin-lts currently targets `main`; alignment with the `testing` model is in progress.

Each image repo consumes `projectbluefin/common`. `projectbluefin/testsuite` gates promotion.

**Git branch model (authoritative):**

| Repo | PR target | Promotion path | Release action |
|---|---|---|---|
| `bluefin` | `testing` | `testing→main` | `execute-release.yml` copies `:testing`→`:stable` |
| `bluefin-lts` | `testing`* | `testing→main` | `execute-release.yml` copies `:testing`→`:lts` |
| `dakota` | `testing` | `testing→main` | `execute-release.yml` fires on push to main |

Never target `main` directly for feature work. `main` receives only squash-merge promotion commits.

### Shared CI building blocks (`projectbluefin/actions`)

All three image repos consume `projectbluefin/actions` reusables:

| Reusable | Callers |
|---|---|
| `reusable-promote-squash.yml` | bluefin, bluefin-lts, dakota |
| `reusable-sync-branches.yml` | bluefin, bluefin-lts, dakota |
| `reusable-release-gate.yml` | called by reusable-promote-squash |
| `reusable-execute-release.yml` | bluefin, bluefin-lts |
| `reusable-vulnerability-scan.yml` | bluefin, bluefin-lts, dakota |

**Before fixing a CI issue here:** check if the broken logic lives in a shared reusable in `projectbluefin/actions`. If so, fix it there first — a single fix propagates to all consumers. See `docs/skills/ci.md` → "CI fix workflow for agents" for the correct PR sequence.

## Repo rules

- All PRs target `testing`. **Never `main`.**
- Merge method: **squash only**.
- No WIP PRs.
- Max 4 open PRs per agent.
- **`main` uses a merge queue (ruleset 17070404).** The automated `auto/promote-testing-to-main` promotion PR targets `main` and therefore enters the merge queue. It requires 2 `projectbluefin/maintainers` approvals plus all gate checks passing before the queue runner merges it. See `docs/skills/ci.md` → "Promotion PR merge queue" for the GraphQL snippet to enqueue.
- **`gh pr merge --auto` is blocked on `main`-targeting PRs.** `--auto` calls `enablePullRequestAutoMerge` which the merge queue ruleset rejects. The `reusable-promote-squash.yml` automation handles enqueue via `enqueuePullRequest` GraphQL when `use_merge_queue: true` is set (bluefin passes this). Do not use `--auto` directly.

## Data donation

Bluefin bugs are data donations.

- `ujust report` captures system state before the issue opens.
- `ujust confirm <issue>` records another real-world hit.
- `ujust verify <issue>` confirms the shipped fix and closes the loop.

**Agent rule:** if an issue says `report: attached`, read the gist first. Treat confirm count as a priority signal. Do not bypass the verification loop without maintainer sign-off. Full details live in [`docs/workflow.md`](docs/workflow.md).

## Mandatory gates

Non-compliance = rejection.

- Read [`docs/SKILL.md`](docs/SKILL.md) before modifying anything.
- **After cloning, run `bash .github/scripts/install-hooks.sh` once** to install the pre-push hook that blocks accidental pushes to `origin` (ublue-os/bluefin).
- Run `just check && pre-commit run --all-files` before every commit.
- **Pre-commit guard:** `no-floating-action-tags` blocks third-party `@main`/`@v*` floating action tags at commit time. `projectbluefin/actions/` and `projectbluefin/bonedigger/` refs are intentional managed tags and are exempted. `projectbluefin/testsuite` is SHA-pinned in `run-testsuite.yml` and managed by Renovate.
- Use Conventional Commits for every commit and PR title.
- Every AI-authored commit must include `Assisted-by: <Model> via <Tool>`.
- Keep open PR count at 4 or fewer.
- Do not open WIP PRs.
- **NEVER interact with repos outside the [`projectbluefin`](https://github.com/projectbluefin) org.** Do not open, comment on, or modify issues, PRs, or code in `ublue-os`, `coreos`, or any other org. Only `projectbluefin/*` repos are in scope.
- **Agents MUST NOT push directly to `main`.** All normal changes go via PR from a feature branch targeting `testing`. `main` only receives squash-merge promotion commits via `auto/promote-testing-to-main`.
- **Releases** are cut by merging the `auto/promote-testing-to-main` PR. `execute-release.yml` fires automatically on merge, re-verifies cosign, and copies `:testing` → `:stable`. No separate weekly-promotion workflow exists.
- **`.github/workflows/`, `Justfile`, and `build_files/` are CODEOWNERS-protected** — PRs touching these paths require maintainer review.

  > **⚠️ Git remote trap:** A pre-push hook blocks any push to a remote named
  > `origin` regardless of its URL. **Always push explicitly:**
  > `git push projectbluefin <branch>`. Verify with `git remote -v` before any push.

## Promotion pipeline — how it works

```
PR merges to testing
  └─ "Testing Images" build fires
       └─ post-testing-e2e.yml fires (on workflow_run, testing branch)
            └─ e2e smoke + common suites run against :testing
                 └─ on success: promote-to-testing publishes verified digest as :testing
                      └─ promote-testing-to-main.yml fires (push: testing)
                           └─ reusable-promote-squash.yml opens/updates auto/promote-testing-to-main PR
                                └─ release gate checks: cosign verify + e2e confirmation
                                     └─ 2 maintainer approvals → merge queue → execute-release.yml
                                          └─ :testing → :stable
```

**`reusable-promote-squash.yml` correctly resolves the e2e gate `head_sha` from `inputs.source_branch`** (`testing` for bluefin). The gate queries post-testing-e2e runs by the testing branch HEAD SHA and marks the PR `release/ready` once a passing run is found.

## PR and issue comment policy

- One comment per PR or issue event, max; combine all findings into a single post.
- **To add information to an issue or PR you authored, edit the body — do not add a new comment.** Use `gh api repos/projectbluefin/<repo>/issues/<n> -X PATCH --field body=@file`. A new comment is only appropriate as a reply to someone else or for a distinct event.
- Do not follow a `gh issue close` (or `gh pr close`) with a separate explanatory comment — put the explanation in the close reason or a single combined comment before closing.
- Do not duplicate GitHub UI state.
- Test reports: what ran, pass/fail, blockers only.
- No diff summaries.
- `@mentions` only when asking for a specific action.
- If nothing actionable needs saying, post nothing.

## Analysis vs. implementation

When asked an analysis question ("what's the fix?", "how should we handle X?", "is there a better approach?"), **answer the question — do not implement**. Only write or change code when explicitly asked to make the change. Discussing a solution and implementing it are separate steps; wait for the user to cross that line.

## Cross-repo file placement

Static system files (udev rules, sysctl, modprobe configs, setup hooks) belong in `projectbluefin/common`, not in this repo. Before creating anything under `system_files/`, check `common` first.

**Never commit directly to `projectbluefin/common`.** Any change there requires a branch + PR, regardless of which repo you are working from. Treat a local checkout of `common` as a separate protected repo — branch, commit, push, open PR.

## Build internals — known traps

- **`build_files/shared/build.sh` is dead code.** It is an unused orchestrator left over from the pre-Stage-1/2 split. The Containerfile calls scripts directly. Do not update, test, or reference it.
- **`/tmp` does not persist across RUN instructions.** Each `RUN` gets a fresh tmpfs. Sentinel or marker files that must survive Stage 1 → Stage 2 must be written to the committed filesystem (e.g. `/lib/modules/<kver>/`, `/var/cache/`). Note: `clean-stage.sh` removes all of `/var/*` except `cache/`, so `/var/cache/` subdirs are the safest persistent scratch space.
- **Initramfs marker file:** `04-install-kernel-akmods.sh` runs dracut in Stage 1 and touches `/lib/modules/<kver>/.bluefin-initramfs-done`. `19-initramfs.sh` in Stage 2 skips dracut when the marker is present (Stage 1 cache hit). Set `FORCE_INITRAMFS=1` to regenerate unconditionally (weekly/stable CI does this).

## BATS unit test conventions

Tests live in `tests/unit/`. Run with `bats tests/unit/` (or a single file). The pattern used across all test files:

- **Sandbox setup:** each `setup()` creates `${SCRIPT_DIR}/.bats-sandbox/<name>.<test_num>.$$` and tears it down in `teardown()`.
- **Stubs:** put stub executables in `${TEST_ROOT}/stub-bin/` and prepend to `PATH`. Scripts that call commands via **absolute paths** (e.g. `/usr/bin/dracut`, `/usr/bin/rpm`) bypass `PATH` — patch them out with `sed` before running:
  ```bash
  sed -e "s|/usr/bin/dracut|dracut|g" original.sh > patched.sh
  ```
- **`source /ctx/...` paths** don't exist outside a container build. Replace inline with a no-op stub during patching:
  ```bash
  sed -e "s|source /ctx/build_files/shared/foo.sh|my_func() { :; }|g" original.sh > patched.sh
  ```
  If the sourced file defines multiple functions, write a minimal stub script to `${TEST_ROOT}/` and replace the source path instead.
- **`local` is only valid inside functions.** Never use `local var=…` at the top level of a stub script.
- **Inline env vars before `run` don't export.** `FOO=1 run bash script` does NOT make `FOO` visible inside the script. Use `export FOO=1` on its own line before `run`.
- **Library scripts** (those that define functions) are tested by sourcing them. **Imperative scripts** (those that execute directly) are tested by running them as a subprocess with a `FAKE_ROOT` or `CLEAN_ROOT` prefix variable for filesystem paths.
- **Tested scripts inventory** (as of current HEAD):

  | Test file | Script under test |
  |---|---|
  | `19-initramfs_test.bats` | `build_files/base/19-initramfs.sh` |
  | `17-cleanup_test.bats` | `build_files/base/17-cleanup.sh` |
  | `18-workarounds_test.bats` | `build_files/base/18-workarounds.sh` |
  | `clean-stage_test.bats` (name may vary) | `build_files/shared/clean-stage.sh` |
  | `copr-helpers_test.bats` | `build_files/shared/copr-helpers.sh` |
  | `disable-repos_test.bats` | `build_files/shared/disable-repos.sh` |
  | `package-lib_test.bats` | `build_files/shared/package-lib.sh` |
  | `validate-repos_test.bats` | `build_files/shared/validate-repos.sh` |
  | `00-image-info_test.bats` | `build_files/base/00-image-info.sh` |
