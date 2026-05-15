# Packaging, Compatibility, And Release

This is the canonical human-readable Linux packaging policy. Machine-readable
target metadata lives in
[`packaging/compatibility-map.yml`](../packaging/compatibility-map.yml). Keep
this file, the compatibility map, the patch tree, and GitHub Actions workflows
in sync.

Current release artifacts are `x86_64` only. The accurate support claim today
is mainstream `x86_64` Linux desktop coverage through AppImage, DEB, RPM,
Flatpak, Snap, and AUR packages. Do not claim "all Linux" until at least
`aarch64`, openSUSE RPM, and Alpine APK/musl targets are built, released, and
smoke-tested.

## State Model

| State | Meaning |
|-------|---------|
| release-gated | CI builds it, `release.yml` waits for it, GitHub releases publish it |
| roadmap patch-ready | patch exists, but workflow, artifact, release integration, or runtime smoke is missing |
| legacy candidate | possible target, but dependency availability must be verified first |
| not primary | outside the current WebKitGTK 4.1/Tauri 2 support baseline |

## Support Matrix

This table is the release and compatibility source of truth. A `release-gated`
row is part of the current release gate. A `roadmap patch-ready` row is not a
released package yet.

| Package target | State | Workflow / artifact | Patch | Runtime smoke | Covered systems / rule | Next action |
|----------------|-------|---------------------|-------|---------------|------------------------|-------------|
| AppImage glibc baseline | release-gated | `build-appimage.yml` / `appimage-linux-baseline` | `appimage/linux-baseline.patch` | remote artifact pass | Portable glibc baseline; not Alpine/musl | keep in release gate |
| Debian 12 DEB | release-gated | `build-deb.yml` / `deb-package-debian12` | `deb/debian.12.patch` | remote artifact pass | Debian 12 | keep in release gate |
| Debian 13 DEB | release-gated | `build-deb.debian.13.yml` / `deb-package-debian13` | `deb/debian.13.patch` | pending | Debian 13 | run Debian 13 artifact smoke |
| Ubuntu 24.04 DEB | release-gated | `build-deb.ubuntu.24.04.yml` / `deb-package-ubuntu2404` | `deb/ubuntu.24.04.patch` | remote artifact pass | Ubuntu 24.04, Linux Mint 22.x, matching Ubuntu 24.04 derivatives | keep in release gate |
| Ubuntu 26.04 DEB | release-gated | `build-deb.ubuntu.26.04.yml` / `deb-package-ubuntu2604` | `deb/ubuntu.26.04.patch` | remote artifact pass | Ubuntu 26.04 and matching Ubuntu 26.04 derivatives | keep in release gate |
| Fedora 43 RPM | release-gated | `build-rpm.fedora.43.yml` / `rpm-package-fedora43` | `rpm/fedora.43.patch` | remote artifact pass | Fedora 43 | keep in release gate |
| Fedora 44 RPM | release-gated | `build-rpm.fedora.44.yml` / `rpm-package-fedora44` | `rpm/fedora.44.patch` | remote artifact pass | Fedora 44 | keep in release gate |
| EL10 / RHEL-family RPM | release-gated | `build-rpm.el10.yml` / `rpm-package-el10` | `rpm/el10.patch` | pending | RHEL 10, CentOS Stream 10, AlmaLinux 10, Rocky Linux 10 | run EL10 artifact smoke |
| Flatpak GNOME 49 | release-gated | `build-flatpak.gnome49.yml` / `flatpak-package-gnome49` | `flatpak/org.gnome.Platform.49.patch` | remote artifact pass | GNOME Platform 49 runtime | keep in release gate |
| Flatpak GNOME 50 | release-gated | `build-flatpak.yml` / `flatpak-package` | `flatpak/org.gnome.Platform.50.patch` | remote artifact pass | GNOME Platform 50 runtime | keep in release gate |
| Snap core24 | release-gated | `build-snap.yml` / `snap-package` | `snap/core24.patch` | remote artifact pass | Snap core24 base | keep in release gate |
| Snap core26 | release-gated | `build-snap.core26.yml` / `snap-package-core26` | `snap/core26.patch` | remote artifact pass | Snap core26 base | keep in release gate |
| AUR Arch package | release-gated | `build-aur.yml` / `aur-arch` | `aur/arch.patch` + `aur/arch.wrapper` | remote artifact pass | Arch, Manjaro, EndeavourOS, Garuda | keep in release gate |
| openSUSE Tumbleweed RPM | roadmap patch-ready | none yet / `rpm-package-opensuse-tumbleweed` planned | `rpm/opensuse.tumbleweed.patch` | no release artifact | openSUSE Tumbleweed | add zypper workflow, release artifact, and runtime smoke |
| openSUSE Leap 16 RPM | roadmap patch-ready | none yet / `rpm-package-opensuse-leap16` planned | `rpm/opensuse.leap.16.patch` | no release artifact | openSUSE Leap 16 | add zypper workflow, release artifact, and runtime smoke |
| Alpine 3.22 APK | roadmap patch-ready | none yet / `apk-package-alpine322` planned | `apk/alpine.3.22.patch` | no release artifact | Alpine 3.22 musl; glibc artifacts are not compatible | add APK/musl workflow, release artifact, and runtime smoke |
| Alpine 3.23 APK | roadmap patch-ready | none yet / `apk-package-alpine323` planned | `apk/alpine.3.23.patch` | no release artifact | Alpine 3.23 musl; glibc artifacts are not compatible | add APK/musl workflow, release artifact, and runtime smoke |
| Ubuntu 22.04 DEB | legacy candidate | none | none | not verified | Jammy-family users should use AppImage until dependencies are verified | verify WebKitGTK 4.1 and Tauri 2 dependencies |
| EL9 RPM | legacy candidate | none | none | not verified | RHEL-family 9 users should use AppImage until dependencies are verified | verify WebKitGTK 4.1 availability in target repos |
| Snap core22 | legacy candidate | none | none | not verified | older Snap base | verify WebKitGTK stage packages and desktop behavior |
| Ubuntu 20.04 DEB | not primary | none | none | not applicable | too old for current WebKitGTK 4.1/Tauri 2 baseline | none |
| Debian 11 DEB | not primary | none | none | not applicable | too old for current WebKitGTK 4.1/Tauri 2 baseline | none |
| EL8 RPM | not primary | none | none | not applicable | too old for current WebKitGTK 4.1/Tauri 2 baseline | none |
| Alpine 3.20 APK | not primary | none | none | not applicable | past listed Alpine support as of the 2026-05-15 baseline check | none |
| 32-bit x86 | not primary | none | none | not applicable | outside the current release architecture plan | none |

Current GitHub releases should contain the 13 `release-gated` artifacts above
plus `SHA256SUMS`.

## Architecture Plan

| Architecture | State | Notes |
|--------------|-------|-------|
| `x86_64` | release-gated | current artifact architecture |
| `aarch64` | roadmap | next practical architecture for AppImage, DEB, RPM, Flatpak, Snap, and AUR |
| `armv7` | experimental | add only if users request it and WebKitGTK/Tauri packaging is available |
| `riscv64` | experimental | requires separate build/test work |

## Compatibility Rules

- Linux Mint, Pop!_OS, Zorin, and similar Ubuntu derivatives use the Ubuntu DEB
  that matches their Ubuntu base.
- Arch derivatives use the AUR target or AppImage.
- RHEL 10, CentOS Stream 10, AlmaLinux 10, and Rocky Linux 10 share the EL10 RPM
  line.
- openSUSE users should use AppImage until openSUSE RPM workflows and smoke
  tests are added.
- Alpine users need future APK/musl packages. Current glibc DEB/RPM/AppImage
  artifacts are not Alpine-compatible.
- Flatpak releases target GNOME Platform runtimes because the app is
  GTK/WebKitGTK-based.

## Patch Policy

A patch file is not a supported package target. A target becomes release-gated
only after it has a workflow, artifact upload, `release.yml` integration, and a
recorded runtime smoke result.

Base Rust source must not hard-code distro WebKitGTK environment values.
Target-specific runtime settings belong in `patches/<package>/<target>.patch`
or in that package family's wrapper/manifest.

Rules:

- `patches/common/` is only for source changes required by every package.
- AppImage, Flatpak, and Snap patches target runtimes, not host distros.
- DEB, RPM, APK, and AUR patches target package-manager/ABI baselines.
- One target owns one patch file. Do not split target behavior across multiple
  patch files.

Patch tree:

```text
patches/
|-- common/fix-tauri-worker-protocol.patch
|-- appimage/linux-baseline.patch
|-- aur/arch.patch
|-- deb/debian.12.patch
|-- deb/debian.13.patch
|-- deb/ubuntu.24.04.patch
|-- deb/ubuntu.26.04.patch
|-- rpm/fedora.43.patch
|-- rpm/fedora.44.patch
|-- rpm/el10.patch
|-- rpm/opensuse.tumbleweed.patch
|-- rpm/opensuse.leap.16.patch
|-- apk/alpine.3.22.patch
|-- apk/alpine.3.23.patch
|-- flatpak/org.gnome.Platform.49.patch
|-- flatpak/org.gnome.Platform.50.patch
|-- snap/core24.patch
`-- snap/core26.patch
```

Runtime settings by baseline:

| Baseline | Runtime fixes |
|----------|---------------|
| Debian 12 | `GDK_GL=disable`, `LIBGL_ALWAYS_SOFTWARE=1`, WebKit renderer disables |
| Debian 13 | `GDK_GL=software`, `GSK_RENDERER=cairo`, WebKit renderer disables |
| Ubuntu 24.04 / 26.04 | Debian 13 settings plus `JSC_useWasmIPInt=false` |
| Fedora 43 / 44 | sandbox disable, `JSC_useWasmIPInt=false`, `GDK_GL=disable` |
| EL10 | same current-WebKitGTK path as Fedora |
| openSUSE roadmap | same current-WebKitGTK conservative path until target smoke tests prove otherwise |
| Alpine roadmap | musl package target plus current-WebKitGTK conservative path |
| Flatpak GNOME 49/50 | runtime-specific WebKitGTK settings for GNOME Platform targets |
| Snap core24/core26 | wrapper/manifest WebKit paths plus package patch behavior |
| AUR | Arch-family wrapper and patch for current WebKitGTK |

All package families also require WebKitGTK 4.1, GTK 3, Account/Verify nested
asset path fixes, and Webpack SRI disabled for Drive, Account, and Verify.

## Release Process

Release flow:

```text
dev -> active build and workflow fixes
main -> stable release source
tags -> release artifacts
```

Do not cut a stable release directly from `dev`. Once `dev` is green, merge the
tested commits into `main`, push `main`, then create or update the release tag
from `main`.

Release checklist:

- `dev` has passing RPM, DEB, AppImage, Flatpak, Snap, and AUR workflows.
- Roadmap patch-ready targets are intentionally excluded from `release.yml`
  unless they completed the promotion checklist.
- Runtime smoke records are updated in this file and
  `packaging/compatibility-map.yml`.
- `main` contains only the tested dev commits intended for release.
- Release tag points at `main`, not `dev`.
- GitHub release contains all 13 release-gated artifacts plus `SHA256SUMS`.

Promotion checklist for roadmap targets:

1. Add a package workflow under `.github/workflows/`.
2. Build inside the target container or a defensible ABI-equivalent container.
3. Apply the target patch.
4. Normalize the output filename with the target label.
5. Upload a uniquely named artifact.
6. Add the workflow and artifact download to `release.yml`.
7. Update this file and `packaging/compatibility-map.yml`.
8. Run and record a runtime smoke test on the target runtime or distro.

## Runtime Verification

A successful GitHub Actions run is useful, but it is not the same thing as
downloading the built package and testing it on the target host.

Runtime smoke boundaries:

- DEB, RPM, and APK artifacts count only against their target distro release or
  declared compatible family.
- Snap artifacts count against their Snap base/runtime.
- Flatpak artifacts count against their GNOME runtime, not the host desktop.
- AppImage is validated against the supported glibc baseline.

Interactive app tests are user-controlled. Automation may download, install,
inspect, and launch an artifact only when requested, but it must not close or
kill a GUI session during login, 2FA, CAPTCHA, Drive load, or file-browsing
checks.

## Local Debug Commands

Remote GitHub Actions workflows are the source of truth for release artifacts.
Use local commands only to debug WebClients or Rust/Tauri compilation.

Clone WebClients first:

```bash
git clone --depth=1 --single-branch --branch main https://github.com/ProtonMail/WebClients.git WebClients
```

Build the frontend locally:

```bash
npm run build:web
```

Debug Rust/Tauri compilation locally:

```bash
cd src-tauri
cargo build --release
```

## Build Metadata

`DISTRO_TYPE` is set at compile time by package workflows. In the current code
it is used only for package-type diagnostics in the injected initialization
script. Worker behavior is controlled by the shared WebClients patch.

`package.json` is the source of truth for the release version. Workflows sync it
into:

- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `aur/PKGBUILD`

## Upstream Baseline Check

Last checked against upstream release information on 2026-05-15:

- Alpine lists 3.23 and 3.22 as current supported stable branches, with 3.21
  still supported until 2026-11-01 and 3.20 past listed support.
- Ubuntu 26.04 LTS was released on 2026-04-23 and is supported until 2031.
- Debian 13 was released on 2025-08-09.
- openSUSE Leap 16 was released in 2025-10 and has 24 months of maintenance.
- Snapcraft 9 supports `core26`, and the core26 base snap is available on the
  stable channel.

Sources:

- https://www.alpinelinux.org/releases/
- https://documentation.ubuntu.com/release-notes/26.04/
- https://www.debian.org/releases/trixie/index
- https://news.opensuse.org/2025/10/01/next-chapter-opens-with-leap-release/
- https://documentation.ubuntu.com/snapcraft/stable/explanation/bases/
- https://snapcraft.io/core26
