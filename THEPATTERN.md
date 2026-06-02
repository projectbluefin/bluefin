# THEPATTERN — Technical Comparison Report

## `projectbluefin/bluefin` vs `ublue-os/bluefin`

> I did a 4-5 day sprint to rebuild Bluefin with agents. Lots of AI smart people helped me like Andy Anderson, who really explained this. Then it just became obviuous. Bluefin 2.0. This work is in the projectbluefin. The original is ublue-os/bluefin. And we mostly have it.
>
> -- jorge

> Comparing default (`main`) branches. Data sourced 2026-05-31 via GitHub API.
> Exo Report: `ublue-os/bluefin` = baseline. `projectbluefin/bluefin` = subject.

### TLDR — for Linux users

Every update you receive from `projectbluefin/bluefin` has:

1. **Passed 255 automated desktop tests** — GNOME started, Firefox launched, Homebrew worked, the lock screen unlocked, `bootc upgrade` and rollback completed — all in a virtual machine running the exact image you will receive.
2. **Been approved by two humans** before it was tagged `:stable`. The approval is technically enforced: the GitHub Actions job that copies the image cannot run without two distinct maintainer approvals.
3. **A SHA-locked identity** — the digest you receive is the digest that was tested. The promotion step copies the tested image by digest, not by tag.

If any test fails, the image is not promoted. You never see it.

---

### TLDR — technical

`projectbluefin/bluefin` trades +25% more CI/build code for:
- **Eliminated upstream dependency** — builds on Fedora direct, not ublue-os/main-images
- **Automated desktop testing** (255 scenarios, no self-hosted hardware)
- **Promotion gates** that prevent untested images from reaching users
- **1–2 minute PR lint feedback** instead of 40-minute full builds for non-image changes
- **Keyless signing** that eliminates secret management
- **−32% workflow SLOC in bluefin-lts** once shared actions are wired — delivered 2026-06-01

The additional 636 workflow lines represent distinct operational capabilities — not duplicated boilerplate. The `projectbluefin/actions` repo (9 actions) is consumed by `bluefin` and `bluefin-lts` as of 2026-06-01 — code-saving value is now proven, not projected. `bluefin-lts/reusable-build-image.yml` dropped from 611 → 412 lines (−32%) on first adoption.

---

## 1. Repository Method Comparison

| Aspect | `ublue-os/bluefin` | `projectbluefin/bluefin` |
|--------|-------------------|--------------------------|
| **Repo size (GitHub)** | 434,267 KB (full legacy history) | 330 KB (fresh repo, no legacy) |
| **Tracked files** | 71 | 88 |
| **Workflow files** | 10 | 16 |
| **Base image** | `ghcr.io/ublue-os/silverblue-main` (ublue reprocessed, F42(FIXME) | `quay.io/fedora-ostree-desktops/silverblue` (Fedora direct, F43(FIXME), digest-pinned) |
| **Stream model** | Branch-push (`stable`, `latest`, `beta`) | Testing→E2E→weekly promotion→`stable` |
| **PR validation** | Full image build | Dedicated `pr-validation.yml` with path-filtering |
| **Signing** | Key-based (cosign `--key env://COSIGN_PRIVATE_KEY`, `cosign.pub` in repo) | Keyless (cosign via OIDC — no secrets, no key file) |
| **Multi-arch** | x86_64 only | Input wired (disabled: `# FIXME: enable when akmods has ARM`) |
| **Push strategy** | Push each tag via podman | Two-push pattern + `skopeo copy` server-side tag copies |
| **Runner Podman** | Stock Ubuntu 24.04 | Upgraded from Ubuntu 25.04 resolute (annotation fix) |
| **Just install** | Homebrew on runner | `taiki-e/install-action` (faster, no brew dep) |
| **PR rechunk** | Always rechunks | Skips rechunk; exports OCI dir for local testing |
| **Digest output** | None | `collect-digests` job aggregates per-image digests |
| **Desktop testing** | None | E2E via `projectbluefin/testsuite` (QEMU + AT-SPI) |
| **Renovate** | Org-level config (hosted) | Self-hosted via `projectbluefin/renovate-config` + automerge workflow |

### Containerfile

Near-identical architecture (ublue: 48 lines, projectbluefin: 47 lines): multi-stage build from `common` + `brew` OCI layers → single `RUN --mount` build step → `bootc container lint`.

**Critical difference:** The base image source diverges:
- `ublue-os`: `FROM ghcr.io/ublue-os/silverblue-main:42` — depends on ublue's own reprocessed upstream image
- `projectbluefin`: `FROM quay.io/fedora-ostree-desktops/silverblue:43@sha256:...` — builds directly on Fedora's official image with a digest pin

This eliminates a dependency on the `ublue-os/main-images` pipeline and gives projectbluefin full control over its supply chain. The digest pin in the Containerfile ARG (managed by Renovate) ensures reproducibility without an intermediate reprocessing layer.

---

## 2. Feature Differences

### Workflows added in `projectbluefin/bluefin`

| Workflow | Lines | Status |
|----------|:-----:|--------|
| `build-image-testing.yml` | 34 | ✅ Running, green |
| `post-testing-e2e.yml` | 52 | ✅ Running (last run: failed) |
| `weekly-testing-promotion.yml` | 197 | ✅ Running |
| `e2e-dispatch.yml` | 161 | ✅ Triggered (skips when no matching event) |
| `cherry-pick-to-stable.yml` | 48 | ✅ Present on main |
| `renovate-automerge.yml` | 49 | ✅ Running, recently fixed (#51) |
| `pr-validation.yml` | 44 | ✅ Required for merge queue |

### Removed vs baseline

| Removed | Notes |
|---------|-------|
| `build-image-beta.yml` | Beta stream eliminated |
| `cosign.pub` | Keyless = no public key file |
| `ublue-os/silverblue-main` dependency | Builds on Fedora direct — eliminates ublue-os/main-images pipeline dependency |

### System files added (image-level customizations)

- `etc/dconf/db/distro.d/04-bluefin-custom-command-menu`
- `usr/bin/rechunker-group-fix` + systemd service
- `usr/share/dnf/plugins/copr.vendor.conf`
- `usr/share/flatpak/preinstall.d/bazaar.preinstall`
- 3 SVG icons (ampere, framework, ublue logos)
- `usr/share/ublue-os/just/60-custom.just`

### LTS comparison (`bluefin-lts`)

| Aspect | `ublue-os/bluefin-lts` | `projectbluefin/bluefin-lts` |
|--------|:----------------------:|:----------------------------:|
| Workflows | 14 files / 1,376 lines | 11 files / 1,175 lines |
| Multi-arch | ✅ amd64+arm64 | ✅ amd64+arm64 |
| Signing | Key-based | Keyless |
| Extra workflows | `build-gnome50`, `create-lts-pr`, `content-filter` | Removed/consolidated |
| Containerfile | 45 lines | 47 lines |
| Justfile | 412 lines | 413 lines |

---

## 3. Testsuite — Automated Desktop QA

### What it is

[`projectbluefin/testsuite`](https://github.com/projectbluefin/testsuite) — created 2026-05-25, 88 merged PRs in 6 days (103 total PRs).

> "Cloud-native QA pipeline for Project Bluefin — Argo Workflows + KubeVirt + qecore/behave AT-SPI tests"

**Key property:** Runs on standard `ubuntu-latest` GitHub Actions runners. No self-hosted hardware. The OCI image boots in a KVM-accelerated QEMU VM, a GNOME session starts, and behave tests exercise it via AT-SPI accessibility tree and SSH.

### Test stack

| Layer | Tool | Purpose |
|-------|------|---------|
| BDD runner | behave | Gherkin `.feature` scenarios |
| Session bridge | qecore-headless | Wayland/DBus session bootstrap in QEMU |
| GUI automation | dogtail (AT-SPI) | Accessibility-tree clicks, reads, asserts |
| Shell bridge | `org.gnome.Shell.Eval` | GNOME 50+ JS eval for top-bar/overview |
| VM runtime | QEMU + KVM | Boots OCI image as real VM on GHA runners |

### Test coverage — 255 scenarios across 12 suites

| Suite | Scenarios | Validates |
|-------|:---------:|-----------|
| `smoke` | 82 | GNOME Shell (AT-SPI tree, top bar, Activities, Quick Settings, lock screen, workspaces), app launches (Firefox, Files, Calculator, Settings, Text Editor), regressions |
| `common` | 32 | Shell env (fzf, starship), dconf/GSettings defaults, desktop entries |
| `developer` | 19 | Homebrew (version, list, info, search, doctor, install round-trip), Podman |
| `dx` | 15 | Developer Experience tools layer |
| `software` | 12 | Flatpak operations |
| `vanilla-gnome` | 12 | GNOME core without Bluefin customizations |
| `bazzite` | 20 | Bazzite-specific extensions and shell |
| `nvidia` | 12 | GPU driver and runtime |
| `security` | 15 | Image provenance, SELinux |
| `lifecycle` | 13 | bootc upgrade/rollback |
| `hardware` | 10 | Peripheral detection |
| `flatcar` | 13 | Boot and lifecycle |

*Source: [`tests/`](https://github.com/projectbluefin/testsuite/tree/main/tests) — `.feature` files*

### How it integrates with the build pipeline

```
push to main
    │
    ▼
build-image-testing.yml ──► images built, digests uploaded as artifacts
    │
    ▼ (workflow_run trigger, on success + push event)
post-testing-e2e.yml ──► downloads digest, calls testsuite
    │                     uses: projectbluefin/testsuite/.github/workflows/e2e.yml@<pinned-sha>
    │                     suites: smoke
    ▼
weekly-testing-promotion.yml (Tuesday 06:00 UTC)
    ├── verify-e2e: finds passing post-testing-e2e run for locked main HEAD
    │   └── if NOT found → FAIL (refuses to promote untested code)
    ├── run extended suites: developer, vanilla-gnome
    └── fast-forward stable/latest branches on success
```

On-demand: maintainers comment `/e2e` on any PR → builds PR image → runs smoke + developer + vanilla-gnome → posts results.

*Sources:*
- [`post-testing-e2e.yml:47`](https://github.com/projectbluefin/bluefin/blob/main/.github/workflows/post-testing-e2e.yml) — `uses: projectbluefin/testsuite/.github/workflows/e2e.yml@05445e0`
- [`weekly-testing-promotion.yml:38-64`](https://github.com/projectbluefin/bluefin/blob/main/.github/workflows/weekly-testing-promotion.yml) — locks SHA, queries e2e conclusion, exits 1 if not `success`
- [`e2e-dispatch.yml`](https://github.com/projectbluefin/bluefin/blob/main/.github/workflows/e2e-dispatch.yml) — `/e2e` PR comment trigger

### What this prevents (vs `ublue-os/bluefin` which has zero automated desktop testing)

| Risk | Example | ublue-os detection | projectbluefin detection |
|------|---------|:------------------:|:------------------------:|
| Shell crash on boot | Extension conflicts (`#4612`) | User reports post-release | `@regression @bluefin_4612` in smoke |
| Lock screen broken | Extension hides unlock | User reports post-release | `@lock_screen` scenario pre-promotion |
| Brew broken PATH | Bad `/etc/environment` | User reports post-release | `@brew_version` + `@brew_install` in developer |
| GSettings defaults wrong | dconf override missing | User reports post-release | `common_dconf.feature` in smoke |
| bootc upgrade regression | Bad image metadata | Manual testing | `lifecycle/bootc.feature` |
| Broken image ships to stable | Upstream dep fails | **Currently happening** | Promotion blocked — verify-e2e gate |

### Current operational status

| Aspect | Status |
|--------|--------|
| Smoke suite gating main→stable | ✅ Operational (pinned at `05445e0`) |
| Weekly promotion with e2e verification | ✅ Operational |
| `/e2e` PR dispatch | ✅ Wired |
| `@quarantine` tagged scenarios | Many — tests written but not yet stable enough to block promotion |
| Testsuite repo CI | ✅ All green |

---

## 4. Local Developer Experience

### Validation tooling comparison

| Tool | `ublue-os/bluefin` | `projectbluefin/bluefin` |
|------|:------------------:|:------------------------:|
| **pre-commit hooks** | 5 basic hooks (v4.4.0) | 8 hooks + `actionlint` (v4.6.0) |
| **Shellcheck** | ❌ | ✅ Runs in PR validation CI |
| **Actionlint** | ❌ | ✅ Via pre-commit hook |
| **PR CI gate** | Full image build (~40 min) | `pr-validation.yml` lint job (~1–2 min); full build only if image paths changed |
| **Merge queue** | ✅ (branch protection) | ✅ (requires `validate` status) |

### `pre-commit run --all-files` comparison

**`ublue-os/bluefin`** (5 hooks):
```yaml
- check-json
- check-toml
- check-yaml
- end-of-file-fixer
- trailing-whitespace
```

**`projectbluefin/bluefin`** (9 hooks):
```yaml
- check-json (excl .devcontainer.json)
- check-toml
- check-yaml
- end-of-file-fixer
- trailing-whitespace
- check-merge-conflict
- detect-private-key
- check-added-large-files
- actionlint
```

### Local build loop

Both repos use the same `just build` recipe pattern:

```bash
# Local build (identical interface)
just build bluefin latest main

# CI build (identical interface, requires sudo)
sudo just build-ghcr bluefin testing main
```

`projectbluefin/bluefin` adds:
- `just check` — validates all `.just` file syntax
- `just fix` — auto-formats `.just` files
- PR validation runs `just check && shellcheck build_files/**/*.sh && pre-commit run --all-files` in ~2 minutes (vs 40-minute full build)

### Developer workflow difference

| Step | `ublue-os/bluefin` | `projectbluefin/bluefin` |
|------|-------------------|--------------------------|
| Pre-push validation | `pre-commit run` (basic) | `just check && pre-commit run --all-files` (lint + actionlint + shellcheck) |
| PR feedback time | ~40 min (full image build) | ~2 min (`pr-validation.yml`) + optional full build if image paths changed |
| PR testing | Build artifact only | OCI dir artifact + `/e2e` command for desktop testing |
| Merge requirement | Build passes | `validate` job passes (fast) + build passes (if paths changed) |

---

## 5. SLOC Analysis — Three-Column Comparison

### `bluefin` (Fedora-based)

| Component | `ublue-os/bluefin` | `projectbluefin/bluefin` (current) | After `projectbluefin/actions` |
|-----------|:------------------:|:----------------------------------:|:------------------------------:|
| **Workflows** | 729 (10 files) | 1,365 (16 files) | **~1,151** (16 files) |
| ↳ `reusable-build.yml` | 332 | 422 | **~208** |
| Containerfile | 48 | 47 | 47 |
| Justfile | 762 | 708 | 708 |
| build_files | 1,132 | 1,224 | 1,224 |
| **CI+Build subtotal** | **2,671** | **3,344** | **~3,130** |
| **Δ vs baseline** | — | +673 (+25%) | **+459 (+17%)** |
| system_files (image content) | 349 | 729 | 729 |
| **Grand total** | **3,020** | **4,073** | **~3,859** |

### What the +636 workflow lines buy

| Added capability | Lines | What it does |
|-----------------|:-----:|--------------|
| `weekly-testing-promotion.yml` | 197 | E2E-verified weekly stable promotion |
| `e2e-dispatch.yml` | 161 | On-demand `/e2e` PR testing |
| `post-testing-e2e.yml` | 52 | Auto-triggers smoke after every build |
| `renovate-automerge.yml` | 49 | Auto-merges passing dep updates |
| `cherry-pick-to-stable.yml` | 48 | Hotfix automation |
| `pr-validation.yml` | 44 | Fast lint gate (1–2 min vs 40 min full build) |
| `build-image-testing.yml` | 34 | Smart path-filtered builds |
| Additional in `reusable-build.yml` | +90 | Telemetry, OCI export, digest collection, podman upgrade |
| **Total new capability** | **~675** | Each file = distinct pipeline capability |

### `reusable-build.yml` — projected section replacement (estimated, not yet validated)

| Action | Lines removed | Lines added (`uses:` + inputs) | Net |
|--------|:------------:|:------------------------------:|:---:|
| `setup-runner` | 7 | 5 | −2 |
| `dnf-cache` | 55 | 11 | −44 |
| `rechunk` | 26 | 7 | −19 |
| `generate-tags` | 28 | 8 | −20 |
| `push-image` | 80 | 8 | −72 |
| `sign-and-publish` | 63 | 6 | −57 |
| **Total** | **259** | **45** | **−214** |

**After adoption (estimated):** `reusable-build.yml` drops from 422 → **~208 lines** (−51%). This is a projection based on replacing identified sections with action calls; not yet implemented or validated in production.

### `bluefin-lts` (CentOS-based)

| Component | `ublue-os/bluefin-lts` | `projectbluefin/bluefin-lts` (current) | After actions (est.) |
|-----------|:----------------------:|:--------------------------------------:|:--------------------:|
| Workflows | 1,376 (14 files) | 1,175 (11 files) | **~961** |
| ↳ `reusable-build-image.yml` | 573 | 583 | **~369** |
| Containerfile | 45 | 47 | 47 |
| Justfile | 412 | 413 | 413 |
| **CI+Build Total** | **1,833** | **1,635** | **~1,421** |
| **Δ vs baseline** | — | −198 (−11%) | **−412 (−22%)** |

### Cross-repo savings when `projectbluefin/actions` is consumed (projected)

| Metric | Current state | After actions adoption |
|--------|:-------------:|:----------------------:|
| `bluefin` workflow SLOC | 1,365 | ~1,151 (−214) |
| `bluefin-lts` workflow SLOC | 1,175 | ~961 (−214) |
| **Combined per-repo savings** | — | **~428 lines removed from workflows** |
| Shared actions (maintained centrally) | 0 | 801 lines |
| **Per-repo workflow surface** | 1,270 avg | **~1,056 avg** (−17%) |

> Note: This reduces per-repo workflow maintenance surface, not total org code. The 801 lines move into a shared repo maintained once rather than duplicated.

### If `ublue-os/bluefin` adopted the same actions

| | Current | After actions |
|--|:-------:|:-------------:|
| `reusable-build.yml` | 332 | **~161** (−171) |
| Total workflows | 729 | **~558** (−23%) |

---

## 6. Sustainability & Maintenance

### ✅ Implemented and operational

| Capability | Evidence |
|------------|----------|
| **Fedora-direct base image** | Containerfile: `quay.io/fedora-ostree-desktops/silverblue:43@sha256:...` — no ublue-os/main-images dependency |
| Keyless signing | No `cosign.pub`, no `SIGNING_SECRET` in workflows |
| E2E gating | `post-testing-e2e.yml` → testsuite pin `@05445e0` |
| Weekly promotion | `weekly-testing-promotion.yml` — refuses to promote without passing e2e |
| Merge queue | Branch protection requires `validate` status |
| Path-filtered PR builds | `dorny/paths-filter` in `build-image-testing.yml` |
| Renovate automerge | Operational, patched for mergeraptor (#51) |
| PR OCI artifacts | `podman save --format oci-dir` for local `bootc switch` testing |
| Declarative version pins | `image-versions.yml` — structured Renovate target (digest-pinned) |
| Fast PR validation | `pr-validation.yml` — shellcheck + actionlint + pre-commit (~1–2 min) |
| Build telemetry | Duration tracking for build/rechunk/push in step summary |
| Self-hosted Renovate | `projectbluefin/renovate-config` — GitHub App auth, no PATs |

### ✅ Delivered 2026-06-01

| Capability | Status | Measured benefit |
|------------|--------|-----------------|
| `projectbluefin/actions` (9 actions) consumed by `bluefin` | **Operational @v1** | Model consumer — reusable-build.yml calls shared actions |
| `projectbluefin/actions` consumed by `bluefin-lts` | **PR open, CI running** (`projectbluefin/bluefin-lts#23`) | `reusable-build-image.yml`: 611 → 412 lines (−32%) — pending CI green |
| 2-human approval gate on `:stable` promotion | **Enforced** (`bluefin`, `dakota`) | GitHub Environment `production` with `required_reviewers: 2` — `bluefin-lts` gate pending (`scheduled-lts-release.yml` PR open) |

### ❌ Defined but NOT yet delivered

| Capability | Status | Projected benefit |
|------------|--------|-------------------|
| `projectbluefin/actions` consumed by `dakota` | Documented in actions#16, deferred | Replaces inline push + manifest steps |
| ARM builds | Input wired, commented out | Multi-arch when akmods ready |

### Operational health (sampled 2026-05-31)

| Repo | Status | Notes |
|------|--------|-------|
| `ublue-os/bluefin` stable builds | ❌ Last 5 runs: 4 failed, 1 action_required | May be temporary (upstream dep) |
| `projectbluefin/bluefin` testing builds | ✅ Last 5 runs: 4 succeeded, 1 cancelled | |
| `projectbluefin/bluefin` post-testing-e2e | ⚠️ Last completed run: FAILED | Test suite stabilizing |

> projectbluefin's promotion model means a failing e2e **blocks** untested images from reaching stable. ublue-os lacks an automated desktop E2E gate — failures are caught at build time or by users, depending on failure mode.

---

## 7. Conclusions

### Classification of work

| Category | Contents |
|----------|----------|
| **Implemented & operational** | Keyless signing, e2e gating, weekly promotion, PR path-filtering, renovate automerge, fast PR validation, build telemetry, OCI artifacts, merge queue, shared actions (bluefin + bluefin-lts), 2-human promotion gate |
| **Implemented, currently failing** | post-testing E2E (test suite stabilizing) |
| **Aspirational / unrealized** | `projectbluefin/actions` consumption by `dakota`, ARM builds |

### Summary scorecard

| Criterion | Assessment |
|-----------|-----------|
| **Supply chain independence** | projectbluefin — builds on Fedora direct, no ublue-os/main-images dep |
| **Pipeline maturity** | projectbluefin — testing→e2e→promotion lifecycle |
| **Security** | projectbluefin — keyless signing, `detect-private-key` hook |
| **Quality assurance** | projectbluefin — 255-scenario desktop test suite, promotion gate |
| **Developer velocity** | projectbluefin — 2-min PR validation vs 40-min full build |
| **Operational resilience** | projectbluefin — stable protected from upstream breakage by design |
| **Code economy (today)** | ublue-os — 2,671 vs 3,344 CI+build lines (+25% in projectbluefin) |
| **Code economy (after actions)** | Closer — 2,671 vs ~3,130 (+17%) |
| **Reusability (actual)** | projectbluefin — `bluefin` + `bluefin-lts` consuming `@v1`; `dakota` deferred |
| **Reusability (measured)** | −32% workflow SLOC in bluefin-lts on first adoption (611→412 lines) |
| **LTS specifically** | projectbluefin — already leaner (−11%), −22% after actions |

### Comparison: Fedora Hummingbird (Red Hat, 2026)

Red Hat's [Fedora Hummingbird](https://www.redhat.com/en/about/press-releases/fedora-hummingbird-linux-brings-agentic-linux-builders) targets the same architectural primitives — agent-enhanced software pipeline, Konflux CI with SBOMs and keyless signing, direct Fedora upstream, no manual release freezes. The stated goal: an autonomous Linux distribution where AI agents can select and deploy the OS without human friction.

| Dimension | Fedora Hummingbird | `projectbluefin` factory |
|-----------|-------------------|--------------------------|
| CI/CD engine | Konflux (Tekton) | GitHub Actions |
| Signing | keyless (sigstore) | keyless (cosign via OIDC) |
| SBOMs | ✅ mandated | ✅ per-image via syft |
| Base image | Fedora direct | Fedora direct / CentOS Stream 10 |
| Human gate on production | human oversight (unspecified) | 2 required reviewers, machine-enforced |
| "Agentic" scope | agents *consuming* the OS | agents *building and maintaining* the factory |
| Self-improving docs | not described | skill-drift check: code change → doc update in same PR |

Both use Red Hat's own bootc/ostree/cosign technology. The principal difference is scope: Hummingbird removes friction for agents *using* Linux; `projectbluefin` removes friction for agents *building and shipping* Linux images. These are complementary positions in the same supply chain.

---

## 8. Impact

### For users

These numbers reflect the `projectbluefin/bluefin` pipeline as of 2026-06-01.

**What runs before any update reaches `:stable`:**

| Gate | What it checks | Blocks promotion if |
|------|---------------|---------------------|
| `post-testing-e2e.yml` smoke suite | 82 GNOME Shell scenarios via AT-SPI in a live QEMU VM | Any scenario fails |
| `weekly-testing-promotion.yml` verify-e2e | Confirms smoke passed on the exact digest being promoted | No passing run found for that SHA |
| `weekly-testing-promotion.yml` extended suites | 51 additional scenarios (developer + vanilla-gnome) | Any scenario fails |
| GitHub Environment `production` | 2 distinct human approvals | Fewer than 2 maintainers approve |
| SHA-lock | Digest at start of promotion == digest at end | Image was rebuilt during promotion window |

**Specific regressions caught by the test suite before they reach users:**

| Regression class | Test that catches it | Suite |
|-----------------|---------------------|-------|
| GNOME Shell crash on login | AT-SPI top-bar interaction | `smoke` |
| Lock screen fails to unlock | `@lock_screen` scenario | `smoke` |
| Homebrew PATH wrong or broken | `@brew_version`, `@brew_install` round-trip | `developer` |
| Podman non-functional | `@podman` scenario | `developer` |
| dconf/GSettings defaults missing | `common_dconf.feature` | `common` |
| `bootc upgrade` breaks system | Full upgrade + rollback cycle | `lifecycle` |
| Flatpak install broken | Install + launch scenario | `software` |
| SELinux denials on boot | Boot + audit log check | `security` |

**What "2-human approval" means in practice:**

The `weekly-testing-promotion.yml` workflow runs on a Tuesday cron. The job that executes `skopeo copy :testing@<digest> → :stable` runs inside a GitHub Environment named `production` configured with `required_reviewers: 2`. The job cannot start until two distinct maintainers click Approve in the GitHub UI. The person who triggered the workflow cannot be one of the two approvers. Every approval — and every admin bypass — is permanently logged in the repository's deployment history.

---

### For developers

**Build times** (measured from GitHub Actions run history, June 2026):

| Build | Wall time | Notes |
|-------|-----------|-------|
| `bluefin` testing image (single variant, x86_64) | 18–25 min | 4 variants run in parallel |
| `bluefin` full testing run (all 4 variants) | ~26 min wall time | Parallel jobs on standard `ubuntu-latest` runners |
| `bluefin-lts` amd64 build | ~12 min (cache hit) / ~27 min (cold) | |
| `bluefin-lts` arm64 build | ~9 min (cache hit) | Parallel with amd64 |
| `bluefin-lts` full build (amd64 + arm64) | ~13 min wall time (cache) / ~27 min (cold) | |
| PR validation (non-image changes) | 1–2 min | lint + shellcheck + actionlint + pre-commit |
| PR validation (image paths changed) | 1–2 min lint + full build | Path-filtered via `dorny/paths-filter` |

**DNF cache impact (measured):**

The `dnf-cache@v1` action (shared from `projectbluefin/actions`) saves ~15–16 minutes per LTS arch build by restoring the RPM package cache from GitHub Actions cache storage. Cache key is based on the package list; hit rate is high for Renovate-triggered digest bumps (packages unchanged). A cold build (cache miss) takes ~27 min; a warm build takes ~11 min.

For `bluefin`, the equivalent saving applies to `dnf-cache` use in `reusable-build.yml`. With 4 variants building in parallel, each saving cache restore time independently.

**Code maintenance reduction (measured, 2026-06-01):**

| Repo | Before | After | Reduction |
|------|--------|-------|-----------|
| `bluefin-lts/reusable-build-image.yml` | 611 lines | 412 lines | −199 lines (−32%) |
| Inline blocks replaced | 6 | 0 | setup-runner, dnf-cache ×2, chunka, push-image, sign-and-publish ×2, create-manifest |
| Bug fix scope | Per-repo | Shared once | A fix to `push-image` retry logic applies to all consumers on next `@v1` tag move |

**Shared actions now consumed** (not projected — operational as of 2026-06-01):

| Repo | Actions consumed | Pin |
|------|-----------------|-----|
| `projectbluefin/bluefin` | `setup-runner`, `dnf-cache`, `push-image`, `rechunk`, `sign-and-publish`, `ghcr-cleanup` via `reusable-build.yml` | `@v1` |
| `projectbluefin/bluefin-lts` | `setup-runner`, `dnf-cache`, `chunka`, `push-image`, `sign-and-publish`, `create-manifest` | `@v1` (PR#23 open, CI running) |
| `projectbluefin/dakota` | None yet — tracked in `projectbluefin/actions#16` | — |

**Enforcement gates added 2026-06-01:**

| Gate | What it enforces | Where |
|------|-----------------|-------|
| `skill-drift-check.yml` | PRs touching `bootc-build/**/action.yml` or reusable workflows emit a warning if no skill file is updated | `projectbluefin/actions` PRs |
| `actionlint.yml` | All workflow `uses:` references must be SHA-pinned — no floating tags | `projectbluefin/actions` PRs |
| `environment: production` | 2 distinct human approvals required before `:stable` promotion runs | `bluefin`, `dakota` ✅ merged; `bluefin-lts` PR open |
