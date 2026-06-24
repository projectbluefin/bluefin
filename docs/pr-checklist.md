# Bluefin PR checklist

## All PRs

- [ ] Base branch is `testing`
- [ ] PR is not marked WIP
- [ ] No more than 4 open PRs for this agent
- [ ] `just check` passes
- [ ] `pre-commit run --all-files` passes
- [ ] PR title and commits use Conventional Commits (`feat:`, `fix:`, `chore:`, ...)
- [ ] PR body includes `Closes #NNN` when shipping issue work
- [ ] AI-authored commits include `Assisted-by: <Model> via <Tool>`
- [ ] No hardcoded secrets or credentials
- [ ] If an agent was used, the author accepts responsibility for the PR

> `just check` and `pre-commit run --all-files` are the default gates before every commit.

## Package changes

### RPM / build script changes (`build_files/**`, `system_files/**`)

- [ ] Package edits are limited to the relevant `build_files/base/` script
- [ ] COPR packages use `copr_install_isolated()` from `build_files/shared/copr-helpers.sh`
- [ ] No mixed Fedora/COPR package arrays or ad-hoc repo enablement
- [ ] Shell changes still pass the PR `shellcheck build_files/**/*.sh` gate
- [ ] Full image builds are only run when the package change actually needs container-level testing

### Flatpak changes (`flatpaks/**`)

- [ ] The right list was edited for the affected image behavior
- [ ] Added Flatpaks are appropriate for Bluefin's Flatpak-first model
- [ ] If behavior changed, note how reviewers can verify it after the next image build

### Brew changes (`brew/**`, shared homebrew files)

- [ ] Formula/cask names are valid for the intended tap
- [ ] Shared tools stay in shared Brewfiles unless there is a documented image-specific reason
- [ ] If adding a new external tap or cask, explain why Bluefin needs it

## Containerfile changes

- [ ] The change fits the Bluefin Containerfile model (`common`/`brew` inputs feeding the base image)
- [ ] Related build args stay aligned with `Justfile` and `reusable-build.yml`
- [ ] Local `just build ...` was run only if the change truly affects image assembly
- [ ] Reviewer notes mention the expected cost: full builds take roughly 30–90 minutes and ~25 GB disk
- [ ] No unrelated churn in image metadata, labels, or stage ordering

## CI / workflow changes

- [ ] Trigger branches are intentional (`testing` for PR validation; `main` for release and promotion workflows)
- [ ] Action pins stay intact or are updated deliberately
- [ ] Artifact names, workflow names, and branch filters stay consistent across dependent workflows
- [ ] E2E (`testsuite` job) is gated to `merge_group` only — never add E2E to per-push PR jobs
- [ ] If behavior changed, this doc set or `docs/ci.md` was updated too

## Shell library changes (`build_files/shared/`)

- [ ] If adding or modifying shell helper functions in `build_files/shared/`, update or add unit tests in `tests/unit/`
- [ ] Run `just test-unit` or `bats tests/unit/` locally to verify all tests pass
- [ ] **Do not place test files in `build_files/`** — files there trigger image path filters and will cause E2E to run on every PR push

## Before asking for review

- [ ] Summary explains the user-visible change in plain language
- [ ] Testing section says exactly what ran locally
- [ ] Bug-fix PRs include community verification instructions when needed
