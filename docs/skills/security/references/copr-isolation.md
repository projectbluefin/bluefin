# COPR isolation invariant

Reference for [`../SKILL.md`](../SKILL.md). The canonical implementation is
`build_files/shared/copr-helpers.sh`; read it before changing the sequence.

## The invariant

`copr_install_isolated <copr_name> <package>...` must keep all three steps, in
order:

1. `dnf5 -y copr enable "$copr_name"` — make the COPR available.
2. `dnf5 -y copr disable "$copr_name"` — immediately disable it.
3. `dnf5 -y install --enablerepo="copr:copr.fedorainfracloud.org:<owner>:<project>" <packages>` —
   install only from the named repository.

Step 2 is **not** cleanup. Disabling the COPR before installing prevents an
enabled COPR from injecting fake versions of Fedora base packages into
subsequent `dnf5 install` calls (repository priority poisoning). Collapsing
this to `copr enable && dnf5 install` breaks the security model.

The helper also refuses an empty package list, so a mistyped call fails loudly
instead of enabling a repository for nothing.

## Transaction ordering

`build_files/base/03-packages.sh` installs all Fedora, Tailscale, and
multimedia packages in one bulk transaction *first*, and only then calls
`copr_install_isolated` for each COPR package. Keep that ordering: bulk Fedora
resolution must not happen while any COPR is enabled.

Tailscale follows the same pattern with a plain repo file — the repository is
added, set to `enabled=0`, and then used via an explicit `--enablerepo`.

## Verification

```bash
cat build_files/shared/copr-helpers.sh
grep -n 'copr_install_isolated\|enablerepo' build_files/base/03-packages.sh
bats tests/unit/copr-helpers_test.bats tests/unit/03-packages_test.bats
```
