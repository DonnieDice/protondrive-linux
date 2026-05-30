---
title: "Packaging, Compatibility, And Release"
created: 2026-05-28
updated: 2026-05-28
type: guide
tags: [packaging, build, release]
sources:
  - []
---


# Packaging, Compatibility, And Release

This is the canonical human-readable Linux packaging policy. Machine-readable
target metadata lives in
[`packaging/compatibility-map.yml`](../packaging/compatibility-map.yml). Keep
this file, the compatibility map, the patch tree, and GitHub Actions workflows
in sync.

Current release artifacts are `x86_64` only. The accurate support claim today
is mainstream `x86_64` Linux desktop coverage through AppImage, DEB, RPM,
Flatpak, Snap, and AUR packages. Do not claim "all Linux" until at least
`aarch64`, openSUSE RPM, Alpine APK/musl, and at least one of Nix/Gentoo/Slackware
targets are built, released, and smoke-tested.

## State Model

| State | Meaning |
|-------|---------|
| release-gated | CI builds it, the release job in `package-workflows.yml` waits for it, GitHub releases publish it |
| roadmap patch-ready | patch exists, but workflow, artifact, release integration, or runtime smoke is missing |
| roadmap | planned target, no patch yet; needs packaging design, workflow, and smoke test |
| legacy candidate | one compatibility gate passes but the other is unverified or failing |
| not primary | both compatibility gates fail or the failing gate has no upgrade path |

## Compatibility Gates

ProtonDrive Linux has **two independent compatibility gates** that must
both be satisfied for a native package target to work:

| Gate | Requirement | What it controls |
|------|-------------|-------------------|
| **glibc / libc** | glibc ≥ 2.35 (or musl for Alpine APK targets) | Whether the compiled Rust/Tauri binary can run on the host C library |
| **WebKitGTK** | WebKitGTK 4.1 (with GTK 3) available in the target repos or runtime | Whether the Tauri 2 webview can render |

A target can pass one gate and fail the other. The two are not coupled:

- **Passes glibc, fails WebKitGTK** — Ubuntu 22.04 (Jammy) ships glibc 2.35
  but does not officially package WebKitGTK 4.1. The binary would run, but
  the webview dependency is missing. These are `legacy candidate` targets.
- **Passes WebKitGTK, fails glibc** — A hypothetical distro with current
  WebKitGTK but a glibc older than 2.35. The library is available but the
  binary cannot link. These are `not primary` targets.
- **Fails both** — Ubuntu 20.04, Debian 11, EL8: too old on both counts.
  These are `not primary` targets.
- **Passes both** — Debian 12+, Ubuntu 24.04+, Fedora 43+, EL10, Arch,
  Alpine (via musl APK), Flatpak GNOME 49+, Snap core24+. These are
  `release-gated` or `roadmap patch-ready`.

The AppImage target is a special case: it bundles its own glibc baseline
and therefore only has a WebKitGTK gate at runtime. The Snap and Flatpak
targets carry their own WebKitGTK inside the runtime/snap, so both gates
are satisfied by the runtime, not the host distro.

### Impact on the Support Matrix

The `glibc` and `WebKitGTK` columns in the support matrix below show the
gate status for each target. A target is `release-gated` only when **both**
gates pass. A `legacy candidate` has one gate passing and one failing or
unverified. A `not primary` target has both gates failing or the failing
gate has no upgrade path.

## Support Matrix

This table is the release and compatibility source of truth. The **glibc**
and **WebKitGTK** columns are the two independent compatibility gates
described above. Both must pass for a target to be `release-gated`.

### Release-gated targets

| Package target | glibc gate | WebKitGTK gate | Workflow / artifact | Patch | Runtime smoke | Covered systems / rule | Next action |
|----------------|-----------|----------------|---------------------|-------|---------------|------------------------|-------------|
| AppImage glibc baseline | bundled (2.35) | host must provide | `appimage/linux-baseline` / `appimage-linux-baseline` | `appimage/linux-baseline.patch` | remote artifact pass | Portable glibc baseline; not Alpine/musl | keep in release gate |
| Debian 12 DEB | pass (2.36) | pass | `deb/debian-12` / `deb-package-debian12` | `deb/debian.12.patch` | remote artifact pass | Debian 12 | keep in release gate |
| Debian 13 DEB | pass (2.38) | pass | `deb/debian-13` / `deb-package-debian13` | `deb/debian.13.patch` | remote artifact pass | Debian 13 | keep in release gate |
| Ubuntu 24.04 DEB | pass (2.39) | pass | `deb/ubuntu-24.04` / `deb-package-ubuntu2404` | `deb/ubuntu.24.04.patch` | remote artifact pass | Ubuntu 24.04, Linux Mint 22.x, matching Ubuntu 24.04 derivatives | keep in release gate |
| Ubuntu 26.04 DEB | pass (2.41) | pass | `deb/ubuntu-26.04` / `deb-package-ubuntu2604` | `deb/ubuntu.26.04.patch` | remote artifact pass | Ubuntu 26.04 and matching Ubuntu 26.04 derivatives | keep in release gate |
| Fedora 43 RPM | pass (2.42) | pass | `rpm/fedora-43` / `rpm-package-fedora43` | `rpm/fedora.43.patch` | remote artifact pass | Fedora 43 | keep in release gate |
| Fedora 44 RPM | pass (2.42) | pass | `rpm/fedora-44` / `rpm-package-fedora44` | `rpm/fedora.44.patch` | remote artifact pass | Fedora 44 | keep in release gate |
| EL10 / RHEL-family RPM | pass (2.39) | pass | `rpm/el10` / `rpm-package-el10` | `rpm/el10.patch` | remote artifact pass | RHEL 10, CentOS Stream 10, AlmaLinux 10, Rocky Linux 10 | keep in release gate |
| openSUSE Tumbleweed RPM | pass | pass | `rpm/opensuse-tumbleweed` / `rpm-package-opensuse-tumbleweed` | `rpm/opensuse.tumbleweed.patch` | remote artifact pass | openSUSE Tumbleweed | keep in release gate |
| Flatpak GNOME 49 | runtime | runtime | `flatpak/gnome-49` / `flatpak-package-gnome49` | `flatpak/org.gnome.Platform.49.patch` | remote artifact pass | GNOME Platform 49 runtime | keep in release gate |
| Flatpak GNOME 50 | runtime | runtime | `flatpak/gnome-50` / `flatpak-package` | `flatpak/org.gnome.Platform.50.patch` | remote artifact pass | GNOME Platform 50 runtime | keep in release gate |
|| Snap core24 | runtime | runtime | `snap/core24` / `snap-package` | `snap/core24.patch` | remote artifact pass | Snap core24 base | blocked: Snap Store publishing blocked (issues #83, #19); CI builds continue but artifacts not included in release until unblocked |
|| Snap core26 | runtime | runtime | `snap/core26` / `snap-package-core26` | `snap/core26.patch` | remote artifact pass | Snap core26 base | blocked: Snap Store publishing blocked (issues #83, #19); CI builds continue on best-effort (`continue-on-error`) until unblocked |
|| AUR Arch package (native build) | pass (glibc 2.39) | pass | `aur/arch-native` / `aur-arch-native` | `aur/arch-native.patch` | remote artifact pass | Arch, Manjaro, EndeavourOS, Garuda | keep in release gate |
| Alpine 3.20 APK | musl pass | pass | `apk/alpine-3.20` / `apk-package-alpine320` | `apk/alpine.3.20.patch` | local smoke pass | Alpine 3.20 musl; glibc artifacts are not compatible | keep in release gate |
| Alpine 3.22 APK | musl pass | pass | `apk/alpine-3.22` / `apk-package-alpine322` | `apk/alpine.3.22.patch` | local smoke pass | Alpine 3.22 musl; glibc artifacts are not compatible | keep in release gate |
| Alpine 3.23 APK | musl pass | pass | `apk/alpine-3.23` / `apk-package-alpine323` | `apk/alpine.3.23.patch` | local smoke pass | Alpine 3.23 musl; glibc artifacts are not compatible | keep in release gate |

### Roadmap patch-ready targets

| Package target | glibc gate | WebKitGTK gate | Workflow / artifact | Patch | Runtime smoke | Covered systems / rule | Next action |
|----------------|-----------|----------------|---------------------|-------|---------------|------------------------|-------------|
| openSUSE Leap 16 RPM | pass | pass | none yet / `rpm-package-opensuse-leap16` planned | `rpm/opensuse.leap.16.patch` | no release artifact | openSUSE Leap 16 | add zypper workflow, release artifact, and runtime smoke |

### Roadmap targets (no patch yet)

| Package target | glibc gate | WebKitGTK gate | Covered systems / rule | Next action |
|----------------|-----------|----------------|------------------------|-------------|
| Nix flake | n/a (Nix manages libc) | pass (nixpkgs provides) | NixOS and any host with Nix | design flake.nix, add CI workflow, create patch, validate smoke test |
| Gentoo ebuild | pass | pass | Gentoo | design ebuild, add CI workflow, create patch, validate smoke test |
| Slackware package | pass | verify | Slackware current; WebKitGTK 4.1 availability must be confirmed for target | verify WebKitGTK 4.1 in Slackware current repos, then design package, workflow, and patch |

### Legacy candidate targets

| Package target | glibc gate | WebKitGTK gate | Covered systems / rule | Next action |
|----------------|-----------|----------------|------------------------|-------------|
| Ubuntu 22.04 DEB | pass (2.35) | unverified | Jammy-family users should use AppImage until dependencies are verified | verify WebKitGTK 4.1 availability in Jammy repos or backports |
| EL9 RPM | pass (2.34) | unverified | RHEL-family 9 users should use AppImage until dependencies are verified | verify WebKitGTK 4.1 availability in EPEL or target repos |
| Snap core22 | runtime | unverified | older Snap base | verify WebKitGTK stage packages and desktop behavior |

### Not-primary targets

| Package target | glibc gate | WebKitGTK gate | Reason | Next action |
|----------------|-----------|----------------|--------|-------------|
| Ubuntu 20.04 DEB | fail (2.31) | fail | Both gates fail; glibc too old and no WebKitGTK 4.1 | none |
| Debian 11 DEB | fail (2.31) | fail | Both gates fail; glibc too old and no WebKitGTK 4.1 | none |
| EL8 RPM | fail (2.28) | fail | Both gates fail; glibc too old and no WebKitGTK 4.1 | none |
| Alpine 3.20 APK | promoted | pass | Promoted to release-gated on 2026-05-16; CI green, smoke test passed on Alpine 3.20 host | none (now in release-gated) |
| Alpine 3.22 APK | promoted | pass | Promoted to release-gated on 2026-05-16; CI green, smoke test passed on Alpine 3.22 host | none (now in release-gated) |

## Architecture Plan

| Architecture | State | Notes |
|--------------|-------|-------|
| `x86_64` | release-gated | current artifact architecture |
| `aarch64` | roadmap | next practical architecture for AppImage, DEB, RPM, Flatpak, Snap, and AUR |
| `armv7` / RPi 2/3 | legacy | 32-bit ARM; WebKitGTK 4.1 cross-compilation and runtime on armv7 must be verified before any workflow is added; RPi 2/3 users can use the AppImage today if their glibc is sufficient, but native packages require a separate armv7 build pipeline |
| `riscv64` | experimental | requires separate build/test work |
| `x86` (32-bit) | legacy | 32-bit x86; not planned for native packages; users on 32-bit x86 should use AppImage if glibc permits, but no CI workflow is planned |

## Compatibility Rules

- Linux Mint, Pop!_OS, Zorin, and similar Ubuntu derivatives use the Ubuntu DEB
  that matches their Ubuntu base.
- Arch derivatives use the AUR target or AppImage.
- The AUR package is a native build that compiles against Arch system
  packages. It replaced the former AppImage-wrapper package
  (`proton-drive-bin`) in v1.4.0. The AUR package is published via
  the AUR publish implementation, which pushes PKGBUILD and .SRCINFO to
  `aur.archlinux.org/proton-drive` on release.
- RHEL 10, CentOS Stream 10, AlmaLinux 10, and Rocky Linux 10 share the EL10 RPM
  line.
- openSUSE Tumbleweed users use the Tumbleweed RPM. Leap 16 users should use AppImage until a Leap 16 RPM workflow and smoke test are added.
- Alpine users need APK/musl packages. Alpine 3.20, 3.22, and 3.23 have
WebKitGTK 4.1 available in repos and are release-gated. Current glibc
DEB/RPM/AppImage artifacts are not Alpine-compatible.
- Flatpak releases target GNOME Platform runtimes because the app is
  GTK/WebKitGTK-based. Flatpak packages are published to Flathub at
  https://flathub.org/apps/com.proton.drive via the Flatpak publish
  implementation. An initial Flathub submission PR to `flathub/flathub` is required
  before the publish workflow can push updates. The reference source-build
  manifest is at `packaging/com.proton.drive.yml`.
- Snap packages are published to the Snap Store at
  https://snapcraft.io/protondrive-linux via the Snap publish implementation.
  Both core24 and core26 bases use
  `confinement: strict`. The `home` plug covers downloads to `~/Downloads`
  and the `removable-media` plug covers USB/mounted drives. No classic
  confinement is needed for the current download-only feature set. When
  2-way sync with arbitrary directories is added, `system-files` or a
  classic confinement request may be required. **Note: Snap Store
  publishing is currently blocked — `snapcraft register` and
  `snapcraft upload` return `resource-not-found` despite the name being
  registered. The `snapcraft names` command also shows no registered
  snaps even after successful registration. This appears to be a
  snapcraft CLI / Snap Store API issue. See issue #83 and #19.**
- Nix users will use a future Nix flake that manages both libc and WebKitGTK
  through nixpkgs. Until then, use the AppImage or Flatpak.
- Gentoo users will use a future ebuild that builds against system packages.
  Until then, use the AppImage or Flatpak.
- Slackware users should use the AppImage until a Slackware package and
  WebKitGTK 4.1 availability on Slackware current are verified.
- armv7 / RPi 2/3 users should use the AppImage if their glibc baseline
  permits. Native armv7 packages are a legacy target pending WebKitGTK
  cross-compilation verification.
- 32-bit x86 users should use the AppImage if their glibc baseline permits.
  No native 32-bit x86 packages are planned.

## Patch Policy

A patch file is not a supported package target. A target becomes release-gated
only after it has a package implementation, artifact upload,
`package-workflows.yml` release integration, and a recorded runtime smoke
result.

Base Rust source must not hard-code distro WebKitGTK environment values.
Target-specific runtime settings belong in `patches/<package>/<target>.patch`
or in that package family's wrapper/manifest.

Rules:

- `patches/common/` is only for source changes required by every package.
- AppImage, Flatpak, and Snap patches target runtimes, not host distros.
- DEB, RPM, APK, and AUR patches target package-manager/ABI baselines.
- Nix and Gentoo patches target build configuration and runtime wrappers
  specific to those package managers.
- One target owns one patch file. Do not split target behavior across multiple
  patch files.

Patch tree:

```text
patches/
|-- common/fix-tauri-worker-protocol.patch
|-- appimage/linux-baseline.patch
|-- aur/arch-native.patch
|-- deb/debian.12.patch
|-- deb/debian.13.patch
|-- deb/ubuntu.24.04.patch
|-- deb/ubuntu.26.04.patch
|-- rpm/fedora.43.patch
|-- rpm/fedora.44.patch
|-- rpm/el10.patch
|-- rpm/opensuse.tumbleweed.patch
|-- rpm/opensuse.leap.16.patch
|-- apk/alpine.3.20.patch
|-- apk/alpine.3.22.patch
|-- apk/alpine.3.23.patch
|-- flatpak/org.gnome.Platform.49.patch
|-- flatpak/org.gnome.Platform.50.patch
|-- snap/core24.patch
|-- snap/core26.patch
|-- nix/flake.patch (roadmap)
|-- gentoo/ebuild.patch (roadmap)
|-- slackware/slackware.current.patch (roadmap)
```

Runtime settings by baseline:

| Baseline | Runtime fixes |
|----------|---------------|
| Debian 12 | `GDK_GL=disable`, `LIBGL_ALWAYS_SOFTWARE=1`, WebKit renderer disables |
| Debian 13 | `GDK_GL=software`, `GSK_RENDERER=cairo`, WebKit renderer disables |
| Ubuntu 24.04 / 26.04 | Debian 13 settings plus `JSC_useWasmIPInt=false` |
| Fedora 43 / 44 | sandbox disable, `JSC_useWasmIPInt=false`, `GDK_GL=disable` |
| EL10 | same current-WebKitGTK path as Fedora |
| openSUSE Tumbleweed | sandbox disable, `JSC_useWasmIPInt=false`, `GDK_GL=disable`, `LIBGL_ALWAYS_SOFTWARE=1`, `GSK_RENDERER=cairo` |
| Alpine 3.20 APK | musl package target; `WEBKIT_DISABLE_DMABUF_RENDERER=1`, `WEBKIT_DISABLE_COMPOSITING_MODE=1`, `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`, `JSC_useWasmIPInt=false`, `GDK_GL=disable`, `LIBGL_ALWAYS_SOFTWARE=1`, `GSK_RENDERER=cairo` |
| Alpine 3.22 APK | Alpine 3.20 settings plus D-Bus session auto-launch, `AT_SPI_BUS_ADDRESS=/dev/null`, `XDG_RUNTIME_DIR` auto-create |
| Alpine 3.23 APK | Alpine 3.22 settings (same D-Bus/at-spi/XDG workarounds) |
| Flatpak GNOME 49/50 | runtime-specific WebKitGTK settings for GNOME Platform targets |
| Snap core24/core26 | wrapper/manifest WebKit paths plus package patch behavior |
| AUR (native) | sandbox disable, `JSC_useWasmIPInt=false`; hardware rendering kept |
| Nix roadmap | nixpkgs-managed WebKitGTK; runtime settings TBD after smoke test |
| Gentoo roadmap | system WebKitGTK; runtime settings TBD after smoke test |
| Slackware roadmap | Slackware current WebKitGTK; runtime settings TBD after smoke test |

All package families also require WebKitGTK 4.1, GTK 3, Account/Verify nested
asset path fixes, and Webpack SRI disabled for Drive, Account, and Verify.

## GitHub Actions Layout

GitHub only discovers workflow files directly under `.github/workflows/`.
This repository keeps one visible entrypoint there:
`.github/workflows/package-workflows.yml`.

Package and maintenance implementations live as local composite actions under
package-type folders:

```text
.github/workflows/
|-- package-workflows.yml
|-- apk/<target>/action.yml
|-- appimage/<target>/action.yml
|-- aur/<target>/action.yml
|-- deb/<target>/action.yml
|-- flatpak/<target>/action.yml
|-- rpm/<target>/action.yml
|-- snap/<target>/action.yml
|-- maintenance/<task>/action.yml
```

The entrypoint owns triggers, permissions, secrets, containers, and release
gating. The nested `action.yml` files own the package-specific build or publish
steps. When adding a target, add a new target folder under the package family
and add a matching job in `package-workflows.yml`; do not add another root
workflow file unless GitHub Actions needs to discover a separate top-level
trigger.

## Release Process

Release flow:

```text
feature branches -> active build and workflow fixes
main -> stable release source
tags -> release artifacts
```

Do not cut a stable release directly from feature branches. Once the tested
commits are merged into `main`, push `main`, then create or update the release
tag from `main`.

Release checklist:

- `main` has passing RPM, DEB, AppImage, Flatpak, Snap, and AUR workflows.
- Publish implementations (`aur/publish`, `snap/publish`, and
  `flatpak/publish`) have their required secrets configured.
- Roadmap patch-ready targets are intentionally excluded from the release job
  in `package-workflows.yml` unless they completed the promotion checklist.
- Runtime smoke records are updated in this file and
  `packaging/compatibility-map.yml`.
- `main` contains only the tested commits intended for release.
- Release tag points at `main`.
- GitHub release contains all release-gated artifacts (Snap core24/core26 CI builds continue but publishing is blocked — see issues #83 and #19) plus `SHA256SUMS`.

Promotion checklist for roadmap targets:

1. Add a package implementation under `.github/workflows/<package>/<target>/`.
2. Build inside the target container or a defensible ABI-equivalent container.
3. Apply the target patch.
4. Normalize the output filename with the target label.
5. Upload a uniquely named artifact.
6. Add the job and artifact download to `package-workflows.yml`.
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
- AUR native (roadmap) counts against Arch current.
- Nix flake (roadmap) counts against the declared nixpkgs channel.
- Gentoo ebuild (roadmap) counts against Gentoo current stable.
- Slackware package (roadmap) counts against Slackware current.

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

## Publishing Workflows

Three publish workflows push packages to their respective stores on release:

| Store | Workflow | Secret required | Target |
|-------|----------|-----------------|--------|
| AUR | `aur/publish` | `AUR_SSH_PRIVATE_KEY` | `aur.archlinux.org/proton-drive` |
| Snap Store | `snap/publish` | `SNAPCRAFT_STORE_CREDENTIALS` | `snapcraft.io/protondrive-linux` |
| Flathub | `flatpak/publish` | `FLATHUB_SSH_PRIVATE_KEY` | `flathub/com.proton.drive` |

All three publish implementations are called from `package-workflows.yml` on
release publication or manual workflow dispatch. The Flathub workflow requires
an initial submission PR to `flathub/flathub`
before it can push updates (see
https://docs.flathub.org/docs/for-app-authors/submission).

## Upstream Baseline Check

Last checked against upstream release information on 2026-05-15:

- Alpine 3.20 has WebKitGTK 4.1 (v2.44.1) available and installed; promoted
from not-primary to roadmap-patch-ready to release-gated on 2026-05-16
after CI green and local smoke test pass. Alpine lists 3.23 and 3.22 as
  current supported stable branches, with 3.21 still supported until
  2026-11-01 and 3.20 past listed support.
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
