# Architecture

## Build model

This is a Containerfile-driven rpm-ostree/bootc image repository, not a
BuildStream repository.

- [`Containerfile`](../Containerfile) defines the image stages.
- [`Justfile`](../Justfile) is the local operator interface.
- `build_files/base/` contains the ordered image scripts.
- `build_files/shared/` contains reusable build helpers.
- `build_files/packages/` contains the declarative package manifest.
- `image-versions.yml` pins the digests of the `common` and `brew` input images.
- `system_files/` contains files copied into the image, including the GNOME
  Shell extension submodules declared in `.gitmodules`.
- `tests/unit/` contains Bats coverage; `tests/coverage/` holds the kcov merge
  tooling.
- `.github/workflows/` contains CI and release callers; orchestration logic
  lives in `projectbluefin/actions`.

`build_files/shared/build.sh` is unused legacy code — nothing in the
`Containerfile` invokes it. Do not update or reference it.

## Stages and cache boundaries

The `Containerfile` separates package installation from the final filesystem
overlay, using two scratch context stages:

- `ctx-build` carries only `build_files/` and `image-versions.yml`.
- `ctx` carries `system_files/` plus the shared files pulled from the `common`
  and `brew` images.

The split is deliberate: buildah folds a mounted stage's image ID into the `RUN`
cache key, so a combined context would make every `system_files/` edit
invalidate the package layer.

- Stage `base-common` runs the package installs (`03-packages.sh`,
  `04-install-kernel-akmods.sh`, `05-override-install.sh`) mounted from
  `ctx-build`.
- Stage `extension-builder` compiles the GNOME Shell extensions.
- Stage `base` overlays `system_files/`, finalizes extensions, cleans up,
  validates repositories, and runs `20-tests.sh`.
- A final step embeds the container-native ISO contract
  (`21-container-native-iso.sh`) and `bootc container lint` closes the build.

Changes to `system_files/` must not invalidate the package layer. Files that
must survive separate container `RUN` instructions belong on the committed
filesystem, not in `/tmp`.

## Local loop

```bash
just check
pre-commit run --all-files
just test-unit
```

Run `just build <image> <tag> <flavor>` only for changes that affect image
assembly, then use `just clean` to reclaim build artifacts. The image, stream,
and flavor matrices are defined at the top of the `Justfile`.

## Source-of-truth rule

When this document disagrees with `Containerfile`, `Justfile`, build scripts,
tests, or workflows, the source wins. Update this document in the same change
when a stable architectural invariant changes.
