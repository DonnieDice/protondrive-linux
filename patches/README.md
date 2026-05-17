# Patches Directory

Patches are organized by package type and ABI/runtime target. The patch tree
contains both release-gated targets and roadmap patch-ready targets.

A patch file is not a binary package. A target becomes release-supported only
after it has a package workflow, artifact upload, release workflow integration,
and a runtime smoke test. The current target verification checklist lives in
[`docs/packaging.md`](../docs/packaging.md) and
[`packaging/compatibility-map.yml`](../packaging/compatibility-map.yml).

## Full Patch Tree

```text
patches/
|-- common/
|   `-- fix-tauri-worker-protocol.patch
|-- appimage/
|   `-- linux-baseline.patch
|-- deb/
|   |-- debian.12.patch
|   |-- debian.13.patch
|   |-- ubuntu.24.04.patch
|   `-- ubuntu.26.04.patch
|-- rpm/
|   |-- fedora.43.patch
|   |-- fedora.44.patch
|   |-- el10.patch
|   |-- opensuse.tumbleweed.patch
|   `-- opensuse.leap.16.patch
|-- apk/
|   |-- alpine.3.20.patch
|   |-- alpine.3.22.patch
|   `-- alpine.3.23.patch
|-- flatpak/
|   |-- org.gnome.Platform.49.patch
|   `-- org.gnome.Platform.50.patch
|-- snap/
|   |-- core24.patch
|   `-- core26.patch
`-- aur/
  `-- arch-native.patch
```

## Release-Gated Patches

These are currently built and published by the release workflow:

- `appimage/linux-baseline.patch`
- `aur/arch-native.patch`
- `deb/debian.12.patch`
- `deb/debian.13.patch`
- `deb/ubuntu.24.04.patch`
- `deb/ubuntu.26.04.patch`
- `flatpak/org.gnome.Platform.49.patch`
- `flatpak/org.gnome.Platform.50.patch`
- `rpm/el10.patch`
- `rpm/fedora.43.patch`
- `rpm/fedora.44.patch`
- `rpm/opensuse.tumbleweed.patch`
- `apk/alpine.3.22.patch`
- `apk/alpine.3.20.patch`
- `snap/core24.patch`
- `snap/core26.patch`

`common/fix-tauri-worker-protocol.patch` is applied to the cloned WebClients
source during package builds. It is common source behavior, not a package
target.

## Roadmap Patch-Ready Patches

These patches exist because the targets are real ABI/package-manager gaps. They
are not release-gated yet.

| Patch | Target | Required before publishing |
|-------|--------|----------------------------|
| `rpm/opensuse.leap.16.patch` | openSUSE Leap 16 | zypper RPM workflow, artifact upload, runtime smoke test |
| `apk/alpine.3.23.patch` | Alpine 3.23 musl | release artifact integration, musl runtime smoke test |

No optional desktop-runtime variants or older GNOME Flatpak patches are
tracked. Flatpak releases target GNOME Platform runtimes because the app is
GTK/WebKitGTK-based.

## Patch Rules

1. Base code is universal. `src-tauri/src/main.rs` must not hard-code distro
   WebKitGTK environment values.
2. Distro/runtime-specific overrides go in `patches/<package>/<target>.patch`
   or in the package wrapper/manifest.
3. `patches/common/` is only for changes every package needs.
4. AppImage, Flatpak, and Snap patches target runtimes.
5. DEB, RPM, APK, and AUR patches target package-manager/ABI baselines.
6. One target owns one patch file. Do not split target behavior across multiple
   patch files.

## Adding a Target

1. Create the patch against the clean repository base.
2. Name it after the ABI/runtime target, for example `ubuntu.24.04.patch`,
   `opensuse.leap.16.patch`, or `alpine.3.23.patch`.
3. Test repository patches with `git apply --check`.
4. For `common/` patches that apply to cloned WebClients, test after
   `scripts/build-webclients.sh` has cloned WebClients.
5. Add the target to `packaging/compatibility-map.yml`.
6. Add or update documentation in `docs/packaging.md`.
7. Promote to release-gated only after a workflow, artifact upload, release
   integration, and runtime smoke test exist.
