# Packaging, Compatibility, And Release

This is the canonical human-readable Linux packaging document. It merges the
release process, compatibility matrix, ABI roadmap, and patch requirements.

Machine-readable target metadata lives in
[`packaging/compatibility-map.yml`](../packaging/compatibility-map.yml). Keep
that map in sync with this document and the workflow files.

## Support States

| State | Meaning |
|-------|---------|
| release-gated | CI builds it, `release.yml` waits for it, GitHub releases publish it |
| roadmap patch-ready | patch exists, but workflow/artifact/runtime test do not |
| legacy candidate | possible target, but dependency availability must be verified first |
| not primary | outside the current WebKitGTK 4.1/Tauri 2 support baseline |

Current release artifacts are `x86_64`. `aarch64` is the next practical
architecture target, but it is not release-gated yet.

## Release-Gated Matrix

`release.yml` currently waits for 13 `x86_64` artifacts:

| Package family | Target | Workflow | Patch | Artifact |
|----------------|--------|----------|-------|----------|
| AppImage | glibc baseline | `build-appimage.yml` | `appimage/linux-baseline.patch` | `appimage-linux-baseline` |
| DEB | Debian 12 | `build-deb.yml` | `deb/debian.12.patch` | `deb-package-debian12` |
| DEB | Debian 13 | `build-deb.debian.13.yml` | `deb/debian.13.patch` | `deb-package-debian13` |
| DEB | Ubuntu 24.04 | `build-deb.ubuntu.24.04.yml` | `deb/ubuntu.24.04.patch` | `deb-package-ubuntu2404` |
| DEB | Ubuntu 26.04 | `build-deb.ubuntu.26.04.yml` | `deb/ubuntu.26.04.patch` | `deb-package-ubuntu2604` |
| RPM | Fedora 43 | `build-rpm.fedora.43.yml` | `rpm/fedora.43.patch` | `rpm-package-fedora43` |
| RPM | Fedora 44 | `build-rpm.fedora.44.yml` | `rpm/fedora.44.patch` | `rpm-package-fedora44` |
| RPM | EL10 | `build-rpm.el10.yml` | `rpm/el10.patch` | `rpm-package-el10` |
| Flatpak | GNOME Platform 49 | `build-flatpak.gnome49.yml` | `flatpak/org.gnome.Platform.49.patch` | `flatpak-package-gnome49` |
| Flatpak | GNOME Platform 50 | `build-flatpak.yml` | `flatpak/org.gnome.Platform.50.patch` | `flatpak-package` |
| Snap | core24 | `build-snap.yml` | `snap/core24.patch` | `snap-package` |
| Snap | core26 | `build-snap.core26.yml` | `snap/core26.patch` | `snap-package-core26` |
| AUR | Arch family | `build-aur.yml` | `aur/arch.patch` + `aur/arch.wrapper` | `aur-arch` |

Release artifacts:

- `proton-drive_*.AppImage`
- `proton-drive_*_debian12_amd64.deb`
- `proton-drive_*_debian13_amd64.deb`
- `proton-drive_*_ubuntu24.04_amd64.deb`
- `proton-drive_*_ubuntu26.04_amd64.deb`
- `proton-drive-*.rpm` for Fedora 43, Fedora 44, and EL10
- `proton-drive_*_gnome49.flatpak`
- `proton-drive_*_gnome50.flatpak`
- `proton-drive_*_core24_amd64.snap`
- `proton-drive_*_core26_amd64.snap`
- `proton-drive-*.pkg.tar.zst` for AUR
- `SHA256SUMS`

## Roadmap Patch-Ready Matrix

These targets are in the patch tree because they are real ABI/package-manager
gaps. They are not release-supported until the missing work is done.

| Package family | Roadmap target | Patch | Missing work |
|----------------|----------------|-------|--------------|
| RPM | openSUSE Tumbleweed | `rpm/opensuse.tumbleweed.patch` | zypper workflow, artifact upload, release integration, runtime smoke test |
| RPM | openSUSE Leap 16 | `rpm/opensuse.leap.16.patch` | zypper workflow, artifact upload, release integration, runtime smoke test |
| APK | Alpine 3.22 | `apk/alpine.3.22.patch` | APK packaging, musl build/test host, artifact upload, release integration |
| APK | Alpine 3.23 | `apk/alpine.3.23.patch` | APK packaging, musl build/test host, artifact upload, release integration |

Do not add these to `release.yml` until their package workflow is green and a
runtime smoke test has been recorded.

## Legacy Candidates

Do not add these to the release gate until dependency availability is verified
on the target image/host.

| Target | Rule |
|--------|------|
| Ubuntu 22.04 | verify WebKitGTK 4.1 and Tauri 2 dependency availability before adding a workflow |
| Snap core22 | verify WebKitGTK stage packages and desktop behavior before adding a workflow |
| EL9 | verify WebKitGTK 4.1 availability in supported repos before adding a workflow |

## Not Primary

| Target | Reason |
|--------|--------|
| Ubuntu 20.04 | too old for current WebKitGTK 4.1/Tauri 2 baseline |
| Debian 11 | too old for current WebKitGTK 4.1/Tauri 2 baseline |
| EL8 | too old for current WebKitGTK 4.1/Tauri 2 baseline |
| Alpine 3.20 | past listed Alpine support as of the 2026-05-15 check |
| 32-bit x86 | outside current release architecture plan |

## Architecture Plan

| Architecture | State | Notes |
|--------------|-------|-------|
| `x86_64` | release-gated | current artifact architecture |
| `aarch64` | roadmap | next practical architecture for AppImage, DEB, RPM, Flatpak, Snap, and AUR |
| `armv7` | experimental | add only if users request it and WebKitGTK/Tauri packaging is available |
| `riscv64` | experimental | requires separate build/test work |

Do not claim "all Linux" until at least `aarch64` artifacts are built and
smoke-tested. The accurate claim today is mainstream `x86_64` Linux desktop
coverage, with patch-ready roadmap entries for openSUSE and Alpine/musl.

## Compatibility Rules

- Linux Mint, Pop!_OS, Zorin, and similar Ubuntu derivatives use the matching
  Ubuntu DEB when their base release matches.
- Arch derivatives use the AUR target or AppImage.
- openSUSE users should use AppImage until openSUSE RPM workflows and tests are
  added.
- Alpine users should use a future APK target only after musl packaging exists;
  glibc packages are not Alpine-compatible.
- Flatpak releases target GNOME Platform runtimes because the app is
  GTK/WebKitGTK-based.

## Patch Inventory

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

## Patch Requirements

Base Rust source must not hard-code distro WebKitGTK environment values.
Target-specific runtime settings belong in `patches/<package>/<target>.patch`
or in that package family wrapper/manifest.

Rules:

- `patches/common/` is only for source changes required by every package.
- AppImage, Flatpak, and Snap patches target runtimes, not host distros.
- DEB, RPM, APK, and AUR patches target package-manager/ABI baselines.
- A patch file does not create a supported release target. A supported target
  also needs a workflow, artifact upload, release workflow integration, and a
  runtime smoke test.

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

The release process is branch-gated:

```text
dev -> active build and workflow fixes
main -> stable release source
tags -> release artifacts
```

Do not cut a stable release directly from `dev`. Once `dev` is green, merge the
tested commits into `main`, push `main`, then create/update the release tag from
`main`.

Release checklist:

- `dev` has passing RPM, DEB, AppImage, Flatpak, Snap, and AUR workflows.
- Roadmap patch-ready targets are either intentionally excluded from
  `release.yml` or have completed the promotion checklist below.
- Runtime smoke tests are recorded for the intended target where available.
- `main` contains only the tested dev commits intended for release.
- Release tag points at `main`, not `dev`.
- GitHub release contains all 13 release-gated artifacts plus `SHA256SUMS`.

## Promotion Checklist

To promote a roadmap patch-ready target to release-gated:

1. Add a package workflow under `.github/workflows/`.
2. Build inside the target container or a defensible ABI-equivalent container.
3. Apply the target patch.
4. Normalize the output filename with the target label.
5. Upload a uniquely named artifact.
6. Add the workflow and artifact download to `release.yml`.
7. Add the target to this document and `packaging/compatibility-map.yml`.
8. Run and record a runtime smoke test on the target runtime/distro.

## Runtime Testing

A successful GitHub Actions run is useful, but it is not the same thing as
downloading the built package and testing it on the target host.

Runtime smoke tests must run on the artifact's intended target:

- DEB/RPM artifacts count only on their matching distro release.
- Snap artifacts count against their Snap base/runtime.
- Flatpak artifacts count against their GNOME runtime, not the host desktop.
- AppImage is validated against the supported glibc baseline.

## Release Verification Checklist

This checklist tracks runtime evidence separately from the release gate. A
release-gated target has workflow, artifact, and release integration. It is not
fully runtime-verified until the built artifact has been exercised on the target
runtime or distro.

| Target | Release gate | Runtime smoke record |
|--------|--------------|----------------------|
| AppImage glibc baseline | yes | remote artifact pass |
| Debian 12 DEB | yes | pending |
| Debian 13 DEB | yes | pending |
| Ubuntu 24.04 DEB | yes | remote artifact pass |
| Ubuntu 26.04 DEB | yes | remote artifact pass |
| Fedora 43 RPM | yes | pending target-host smoke record |
| Fedora 44 RPM | yes | pending target-host smoke record |
| EL10 RPM | yes | pending |
| Flatpak GNOME 49 | yes | pass |
| Flatpak GNOME 50 | yes | remote artifact pass |
| Snap core24 | yes | remote artifact pass |
| Snap core26 | yes | remote artifact pass on Ubuntu 26.04/core26 |
| AUR Arch package | yes | pending target-host smoke record |

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

## DISTRO_TYPE

Each build sets `DISTRO_TYPE` at compile time. In the current code it is used
only for package-type diagnostics in the injected initialization script. Worker
behavior is controlled by the shared WebClients patch.

## Version Source

`package.json` is the source of truth. Workflows sync it into:

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
