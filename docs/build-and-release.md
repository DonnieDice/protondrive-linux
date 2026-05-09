# Build And Release

The release process is branch-gated. Build and workflow fixes land on `dev` first. `main` is for stable releases after the required package workflows pass.

## Branch Policy

```text
dev  -> active build and workflow fixes
main -> stable release source
tags -> release artifacts
```

Do not cut a stable release directly from `dev`. Once `dev` is green, fast-forward or merge the tested commits into `main`, push `main`, then create/update the release tag from `main`.

## Required Release Workflows

These workflows are required for the current release gate:

| Workflow | Artifact | Target |
|----------|----------|--------|
| `build-rpm.fedora.40.yml` | `.rpm` | Fedora 40 release gate; validated on Fedora 41 with the same artifact |
| `build-deb.yml` | `.deb` | Debian/Ubuntu/Mint/Zorin installs |
| `build-appimage.yml` | `.AppImage` | Portable Linux installs |
| `build-aur.yml` | `.SRCINFO` validation | Arch/AUR package metadata |
| `generate-package-specs.yml` | source packaging specs | downstream packaging |

Snap and Flatpak are intentionally outside the current required gate. Restore them as separate workflows after the native package release path is stable.

## Local Build Commands

Clone WebClients first:

```bash
git clone --depth=1 --single-branch --branch main https://github.com/ProtonMail/WebClients.git WebClients
```

Build the frontend and one package type:

```bash
scripts/rpm/build-local-rpm.fedora.40.sh
scripts/deb/build-local-deb.sh
scripts/appimage/build-local-appimage.sh
scripts/flatpak/build-local-flatpak.sh
scripts/snap/build-local-snap.sh
```

If WebClients is already built:

```bash
scripts/rpm/build-local-rpm.fedora.40.sh --skip-webclient
scripts/deb/build-local-deb.sh --skip-webclient
scripts/appimage/build-local-appimage.sh --skip-webclient
scripts/flatpak/build-local-flatpak.sh --skip-webclient
scripts/snap/build-local-snap.sh --skip-webclient
```

## Release Checklist

- `dev` has passing RPM, DEB, AppImage, AUR validation, and generated package spec workflows.
- Fedora/RPM local install has been validated.
- Ubuntu/DEB and AppImage smoke tests are recorded when available.
- `main` contains only the tested dev commits intended for release.
- Release tag points at `main`, not `dev`.
- GitHub release contains `.rpm`, `.deb`, `.AppImage`, and `SHA256SUMS`.

## Version Source

`package.json` is the source of truth. Workflows sync it into:

- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `aur/PKGBUILD`

## Current v1.1.5 Status

Fedora local validation passed through login, CAPTCHA, 2FA, app selection, and Drive launch. The Fedora 40 RPM artifact was also installed and smoke-tested successfully on Fedora 41. CI package workflows are being split and stabilized on `dev` before final promotion to `main`.