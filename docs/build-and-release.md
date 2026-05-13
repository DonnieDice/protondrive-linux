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

These workflows are required for the current release gate (`release.yml` waits for all 14 builds):

| Workflow | Artifact | Target |
|----------|----------|--------|
| `build-rpm.fedora.43.yml` | `.rpm` | Fedora 43 |
| `build-rpm.fedora.44.yml` | `.rpm` | Fedora 44 |
| `build-rpm.el10.yml` | `.rpm` | RHEL 10 / CentOS Stream 10 / Alma 10 / Rocky 10 |
| `build-deb.yml` | `.deb` | Debian 12 |
| `build-deb.debian.13.yml` | `.deb` | Debian 13 |
| `build-deb.ubuntu.22.04.yml` | `.deb` | Ubuntu 22.04 LTS |
| `build-deb.ubuntu.24.04.yml` | `.deb` | Ubuntu 24.04 LTS |
| `build-deb.ubuntu.26.04.yml` | `.deb` | Ubuntu 26.04 LTS |
| `build-appimage.yml` | `.AppImage` | Portable Linux installs (glibc 2.35+) |
| `build-flatpak.yml` | `.flatpak` | Flatpak (org.gnome.Platform//50) |
| `build-snap.yml` | `.snap` | Snap core24 |
| `build-snap.core26.yml` | `.snap` | Snap core26 |
| `build-aur.yml` | `.pkg.tar.zst` | Arch / AUR |

RHEL/Alma/Rocky/CentOS Stream 9 is not a native RPM release target for current builds. The current Tauri/GTK dependency graph requires `glib-2.0 >= 2.70`; EL9 ships `glib2 2.68.x`, so a valid EL9 RPM cannot be produced without downgrading the app stack.

## Local Debug Commands

Remote GitHub Actions workflows are the source of truth for release artifacts. Local build scripts exist to reproduce workflow failures, test patches quickly, and inspect package contents before pushing.

Clone WebClients first:

```bash
git clone --depth=1 --single-branch --branch main https://github.com/ProtonMail/WebClients.git WebClients
```

Build the frontend and one package type locally:

```bash
scripts/rpm/build-local-rpm.fedora.43.sh
scripts/rpm/build-local-rpm.fedora.44.sh
scripts/rpm/build-local-rpm.fedora.40.sh    # legacy, still available
scripts/rpm/build-local-rpm.fedora.41.sh    # legacy, still available
scripts/rpm/build-local-rpm.fedora.42.sh    # legacy, still available
scripts/deb/build-local-deb.sh
scripts/deb/build-local-deb.ubuntu.22.04.sh
scripts/appimage/build-local-appimage.sh
scripts/flatpak/build-local-flatpak.sh
scripts/flatpak/build-local-flatpak.gnome44.sh
scripts/snap/build-local-snap.sh
scripts/build-local-aur.sh
```

If WebClients is already built:

```bash
scripts/rpm/build-local-rpm.fedora.43.sh --skip-webclient
scripts/deb/build-local-deb.ubuntu.22.04.sh --skip-webclient
scripts/appimage/build-local-appimage.sh --skip-webclient
scripts/flatpak/build-local-flatpak.sh --skip-webclient
scripts/flatpak/build-local-flatpak.gnome44.sh --skip-webclient
scripts/snap/build-local-snap.sh core24 --skip-webclient
```

## Release Checklist

- `dev` has passing RPM, DEB, AppImage, Flatpak, Snap, and AUR workflows.
- Fedora/RPM local install has been validated.
- Ubuntu/DEB and AppImage smoke tests are recorded when available.
- `main` contains only the tested dev commits intended for release.
- Release tag points at `main`, not `dev`.
- GitHub release contains all 14 package artifacts plus `SHA256SUMS`.

## Version Source

`package.json` is the source of truth. Workflows sync it into:

- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `aur/PKGBUILD`
