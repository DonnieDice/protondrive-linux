# Build And Release

The release process is branch-gated. Build and workflow fixes land on `dev` first. `main` is for stable releases after the required package workflows pass.

## Branch Policy

```text
dev -> active build and workflow fixes
main -> stable release source
tags -> release artifacts
```

Do not cut a stable release directly from `dev`. Once `dev` is green, fast-forward or merge the tested commits into `main`, push `main`, then create/update the release tag from `main`.

## Required Release Workflows

These workflows are required for the current release gate (`release.yml` waits for all 13 builds):

| Workflow | Artifact | Target |
|----------|----------|--------|
| `build-rpm.fedora.43.yml` | `.rpm` | Fedora 43 |
| `build-rpm.fedora.44.yml` | `.rpm` | Fedora 44 |
| `build-rpm.el10.yml` | `.rpm` | RHEL 10 / CentOS Stream 10 / Alma 10 / Rocky 10 |
| `build-deb.yml` | `.deb` | Debian 12 |
| `build-deb.debian.13.yml` | `.deb` | Debian 13 |
| `build-deb.ubuntu.24.04.yml` | `.deb` | Ubuntu 24.04 LTS |
| `build-deb.ubuntu.26.04.yml` | `.deb` | Ubuntu 26.04 LTS |
| `build-appimage.yml` | `.AppImage` | Portable Linux installs (glibc 2.35+) |
| `build-flatpak.gnome49.yml` | `.flatpak` | Flatpak (org.gnome.Platform//49) |
| `build-flatpak.yml` | `.flatpak` | Flatpak (org.gnome.Platform//50) |
| `build-snap.yml` | `.snap` | Snap core24 |
| `build-snap.core26.yml` | `.snap` | Snap core26 |
| `build-aur.yml` | `.pkg.tar.zst` | Arch / AUR |

## Local Debug Commands

Remote GitHub Actions workflows are the source of truth for release artifacts. The repo no longer keeps package-specific local build wrappers; use the package workflows for release artifacts and use local commands only to debug WebClients or Rust/Tauri compilation.

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

## Release Checklist

- `dev` has passing RPM, DEB, AppImage, Flatpak, Snap, and AUR workflows.
- Fedora/RPM local install has been validated.
- Ubuntu/DEB and AppImage smoke tests are recorded when available.
- `main` contains only the tested dev commits intended for release.
- Release tag points at `main`, not `dev`.
- GitHub release contains all 13 package artifacts plus `SHA256SUMS`.

## Runtime Test Notes

The table below tracks the artifact smoke tests we have personally confirmed. A successful GitHub Actions run is still useful, but it is not the same thing as downloading the built package and testing it on the target host.

Remote artifacts from the `dev` branch package workflows are the release gate. Local builds are used only to debug workflow/package failures.

Runtime smoke tests must run on the artifact's intended target:

- DEB/RPM artifacts count only on their matching distro release (`debian12` on Debian 12, `ubuntu26.04` on Ubuntu 26.04, `el10` on EL10, etc.).
- Snap artifacts count against their Snap base/runtime (`core24` or `core26`) on a host that supports that base.
- Flatpak artifacts count against their GNOME runtime (`org.gnome.Platform//49` or `//50`), not the host desktop version.
- AppImage is the portable target and is validated against the supported glibc baseline.

Record test results for:

- `proton-drive_*_ubuntu24.04_amd64.deb`
- `proton-drive_*_ubuntu26.04_amd64.deb`
- `proton-drive_*_linux-baseline_amd64.AppImage`
- `proton-drive_*_gnome49.flatpak`
- `proton-drive_*_gnome50.flatpak`
- `proton-drive_*_core24_amd64.snap`
- `proton-drive_*_core26_amd64.snap`

Current status:

- Ubuntu 24.04 DEB: remote artifact pass
- Ubuntu 26.04 DEB: remote artifact pass
- Debian 12 DEB: pass
- Flatpak GNOME 49: pass
- Snap core24: remote artifact pass
- AppImage: remote artifact pass
- Flatpak GNOME 50: remote artifact pass
- Snap core26: remote artifact pass on Ubuntu 26.04

Ubuntu 26.04 artifacts are tracked separately from Ubuntu 24.04 artifacts. A passing 26.04 DEB on an Ubuntu 24.04 host does not count as Ubuntu 26.04 compatibility evidence, and Debian artifacts do not count when tested on Ubuntu.

Pending compatibility checks:

- Debian 13 DEB
- EL10 RPM

## Manual Runtime Testing Guardrails

Interactive app tests are user-controlled. Automation may download, install, inspect, and launch an artifact only when requested, but it must not close or kill a GUI session during login, 2FA, CAPTCHA, Drive load, or file-browsing checks.

- Do not wrap GUI launches in `timeout`, `kill`, `pkill`, or similar automatic stop commands.
- If a test app is launched from automation, leave it running until the tester explicitly says to stop it.
- Prefer artifact inspection for non-interactive checks, and let the tester perform credentialed login flows.
- Do not close runtime/login GitHub issues until the tester confirms the relevant artifact reaches the expected screen or file view.

## Version Source

`package.json` is the source of truth. Workflows sync it into:

- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `aur/PKGBUILD`
