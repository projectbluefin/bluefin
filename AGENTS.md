# AGENTS.md

Bluefin is [`projectbluefin/bluefin`](https://github.com/projectbluefin/bluefin): a Containerfile-driven rpm-ostree GNOME desktop image.

**Read [`docs/SKILL.md`](docs/SKILL.md) before doing any work.** Load only the docs that match the task.

> **Before using any tool or library: look up its docs via Context7 first. Always.**
> bootc, cosign, skopeo, buildah, GitHub Actions, rpm-ostree — every tool has live, authoritative docs.
> Pattern: `resolve-library-id` → `get-library-docs` → implement → cite the section.
> Guessing, flag-hunting, and trial-and-error are banned. The docs exist. Read them.
>
> **Before implementing anything CI-related: check how the other repos in the org do it.**
> `dakota`, `bluefin-lts`, and `bluefin` share the same `projectbluefin/actions` reusables.
> If one repo already solved the problem, copy the pattern — do not invent a new one.

## Docs router

- [`docs/SKILL.md`](docs/SKILL.md) — task router
- [`docs/workflow.md`](docs/workflow.md) — issue lifecycle, bonedigger, labels, PR policy
- [`docs/pr-checklist.md`](docs/pr-checklist.md) — PR gates by change type
- [`docs/build.md`](docs/build.md) — build model and local validation loop
- [`docs/skills/ci.md`](docs/skills/ci.md) — CI workflows, triggers, and failure modes

## Org pipeline — projectbluefin

### Repo map

```text
common ──────────────────────────┐
(shared OCI layer)               │
                                 ▼
bluefin  (PRs→testing; testing→main via promotion PR; main→:stable on release)
bluefin-lts (PRs→testing; testing→main; main→lts on release)
dakota  (PRs→testing; testing→main via promotion PR; main→:stable on release)
                                 │
                                 ▼
                                iso (installation media)
```

bluefin-lts → testing → main  (testing-first migration complete)

Each image repo consumes `projectbluefin/common`. `projectbluefin/testsuite` gates promotion.

**Git branch model (authoritative):**

| Repo | PR target | Promotion path | Release action |
|---|---|---|---|
| `bluefin` | `testing` | `testing→main` | `execute-release.yml` copies `:testing`→`:stable` |
| `bluefin-lts` | `testing` | `testing→main` | `execute-release.yml` copies `:testing`→`:lts` |
| `dakota` | `testing` | `testing→main` | `execute-release.yml` fires on push to main |

Never target `main` directly for feature work in `bluefin`, `bluefin-lts`, or `dakota`. All three repos use testing-first development.

### Shared CI building blocks (`projectbluefin/actions`)

All three image repos consume `projectbluefin/actions` reusables:

| Reusable | Callers |
|---|---|
| `reusable-build.yml` | bluefin, bluefin-lts, dakota |
| `reusable-promote-squash.yml` | bluefin, bluefin-lts, dakota |
| `reusable-sync-branches.yml` | bluefin, bluefin-lts, dakota |
| `reusable-release-gate.yml` | bluefin-lts, dakota |
| `reusable-execute-release.yml` | bluefin, bluefin-lts |
| `reusable-vulnerability-scan.yml` | bluefin, bluefin-lts, dakota |
| `reusable-renovate-automerge.yml` | bluefin, bluefin-lts, dakota |
| `reusable-release-reminder.yml` | bluefin, bluefin-lts, dakota |
| `skill-drift-check.yml` | bluefin, bluefin-lts, dakota, actions |

**Before fixing a CI issue here:** check if the broken logic lives in a shared reusable in `projectbluefin/actions`. If so, fix it there first — a single fix propagates to all consumers. See `docs/skills/ci.md` → "CI fix workflow for agents" for the correct PR sequence.

## Repo rules

- All PRs target `testing`. **Never `main`.**
- Merge method: **squash only**.
- No WIP PRs.
- Max 4 open PRs per agent.
- Before opening a PR, check for existing ones covering the same work:
  `gh pr list --repo projectbluefin/bluefin --state open --search "<topic>"`
  If one exists, comment on it rather than opening a duplicate.
- **`main` uses a merge queue (ruleset 17070404).** The automated `auto/promote-testing-to-main` promotion PR enters the merge queue with **0 approvals required** — fully automated. See `docs/skills/ci.md` for the pipeline.
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
- **After cloning, run `bash .github/scripts/install-hooks.sh` once** to install the pre-push hook that blocks accidental pushes to `origin` (projectbluefin/bluefin).
- Run `just check && pre-commit run --all-files` before every commit.
- Never use `git add -A` or `git add .`. After any script execution, build step, or cross-repo checkout:
  `git status`                        # check for unexpected tracked paths
  `git diff --cached --name-only`     # verify only intended files are staged
  Nested .git directories stage as gitlinks and silently corrupt history.
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
  └─ "Testing Images" build fires (publish_stream_tag: false — no :testing tag yet)
       └─ post-testing-e2e.yml fires (on workflow_run, branches: main+testing)
            └─ e2e smoke + common suites run
                 └─ promote-testing-to-main.yml fires (push to testing)
                      └─ reusable-promote-squash.yml opens/updates auto/promote-testing-to-main PR
                           └─ pr-release-gate: cosign verify + smoke,common E2E gate runs inside reusable-promote-squash.yml
                                └─ merge queue → squash-merge to main (0 approvals required)
                                     └─ execute-release.yml: :testing → :stable
                                     └─ sync-main-to-testing.yml: merges main→testing; deletes promotion branch
                                          └─ build on main: post-testing-e2e promote-to-testing job tags :testing
```

**Key facts:**
- `:testing` tag is applied by `post-testing-e2e.yml → promote-to-testing` and **only** when `head_branch == 'main'` (after a build triggered by a push to `main`, not `testing`)
- `execute-release.yml` triggers by commit message pattern, not a schedule — no `weekly-testing-promotion.yml` exists
- `promote-testing-to-main.yml` uses the merge queue (`enqueuePullRequest` GraphQL) — `gh pr merge --auto` is blocked
- **Merge queue requires `validate=success` on BOTH the PR HEAD and the merge group HEAD** (`gh-readonly-queue/main/pr-NNN-...` SHA). `pr-validation.yml` should post the merge group check via `merge_group` event; if it doesn't fire (e.g. `main`/`testing` workflow files diverged), post manually: `gh api repos/projectbluefin/bluefin/statuses/<merge-group-sha> --method POST -f state=success -f context=validate -f description="..."`
- **`promote-testing-to-main.yml` fails with `protected branch hook declined`** when trying to update `auto/promote-testing-to-main` while it is locked in the merge queue. Expected transient — wait for queue to finish or time out (15 min), then re-run: `gh workflow run promote-testing-to-main.yml --repo projectbluefin/bluefin --ref testing`

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

## Self-Improvement

Every session produces two outputs: **the work** and **the learning**.

- Did I discover a workaround, pattern, or convention? → Update or create a skill file in `docs/skills/`.
- Skill file goes in the **same PR** as the work. Not a follow-up.

**Banned:** No changelog files (CHANGELOG.md, IMPROVEMENTS.md, SESSION.md). No session notes committed to the repo. No "append here" instructions — route learnings to the matching skill file.

Before marking work done:
- [ ] Discovered a workaround, pattern, or convention?
- [ ] Skill file updated or created?
- [ ] Committed in this same PR?

Full mandate: [`docs/skills/skill-improvement.md`](docs/skills/skill-improvement.md)

## Cross-repo file placement

Static system files (udev rules, sysctl, modprobe configs, setup hooks) belong in `projectbluefin/common`, not in this repo. Before creating anything under `system_files/`, check `common` first.

**Never commit directly to `projectbluefin/common`.** Any change there requires a branch + PR, regardless of which repo you are working from. Treat a local checkout of `common` as a separate protected repo — branch, commit, push, open PR.

## Build internals — known traps

- **`build_files/shared/build.sh` is dead code.** It is an unused orchestrator left over from the pre-Stage-1/2 split. The Containerfile calls scripts directly. Do not update, test, or reference it.
- **`/tmp` does not persist across RUN instructions.** Each `RUN` gets a fresh tmpfs. Sentinel or marker files that must survive Stage 1 → Stage 2 must be written to the committed filesystem (e.g. `/lib/modules/<kver>/`, `/var/cache/`). Note: `clean-stage.sh` removes all of `/var/*` except `cache/`, so `/var/cache/` subdirs are the safest persistent scratch space.
- **Initramfs marker file:** `04-install-kernel-akmods.sh` runs dracut in Stage 1 and touches `/lib/modules/<kver>/.bluefin-initramfs-done`. `19-initramfs.sh` in Stage 2 skips dracut when the marker is present (Stage 1 cache hit). Set `FORCE_INITRAMFS=1` in the build environment to regenerate unconditionally.

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
