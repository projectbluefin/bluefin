# COPR isolation security invariant

> See also: [`docs/skills/security.md`](security.md) for general COPR usage, cosign, and shellcheck coverage.

## Rule

Keep the `copr_install_isolated` helper as a three-step sequence:

1. `dnf5 -y copr enable <copr>`
2. `dnf5 -y copr disable <copr>`
3. `dnf5 -y install --enablerepo=<repo_id> <packages...>`

Do not collapse this into `copr enable && dnf5 install`.

## Why this is a security boundary

Step 2 is not cleanup. It disables the COPR before the install so the repo is only available to the explicit `--enablerepo=` call. That prevents a COPR from staying globally enabled and trying to satisfy later `dnf5 install` transactions with fake or higher-versioned Fedora base packages.

In other words, the helper is defending against repo priority poisoning: a third-party COPR must not remain active long enough to influence unrelated package resolution.

## Safe pattern

```bash
copr_install_isolated "owner/project" "package-name"
```

## Unsafe pattern

```bash
dnf5 -y copr enable "owner/project"
dnf5 -y install "package-name"
```

The unsafe pattern leaves the COPR enabled for the whole transaction set and weakens the repo trust boundary.

## Where this matters

- `build_files/shared/copr-helpers.sh`
- `build_files/base/03-packages.sh`

If you need to change COPR-related install logic, preserve the enable → disable → install sequence and document why in the commit.
