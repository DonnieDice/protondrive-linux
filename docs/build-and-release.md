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
| `build-rpm.fedora.40.yml` | `.rpm` | Fedora 40/41 compat baseline |
| `build-rpm.fedora.42.yml` | `.rpm` | Fedora 42/43/44 compat baseline |
| `build-rpm.fedora.44.yml` | `.rpm` | Fedora 42/43/44 compat baseline (F44 build container) |
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
scripts/rpm/build-local-rpm.fedora.42.sh
scripts/rpm/build-local-rpm.fedora.43.sh
scripts/rpm/build-local-rpm.fedora.44.sh
scripts/deb/build-local-deb.sh
scripts/appimage/build-local-appimage.sh
scripts/flatpak/build-local-flatpak.sh
scripts/snap/build-local-snap.sh
```

If WebClients is already built:

```bash
scripts/rpm/build-local-rpm.fedora.40.sh --skip-webclient
scripts/rpm/build-local-rpm.fedora.42.sh --skip-webclient
scripts/rpm/build-local-rpm.fedora.43.sh --skip-webclient
scripts/rpm/build-local-rpm.fedora.44.sh --skip-webclient
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

**RPM compatibility baselines validated:**

- `fedora40-compat` RPM: validated locally and on Fedora 41 (login, CAPTCHA, 2FA, Drive launch). Does NOT work on Fedora 42+ (missing webkit2gtk 2.52+ fixes). Confirmed crash on Fedora 44.
- `fedora42-compat` RPM: validated on Fedora 42, Fedora 43, and Fedora 44 (local + remote CI builds, login through 2FA and Drive launch). Fixes: `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` and `JSC_useWasmIPInt=false`.

DEB, AppImage, and AUR CI workflows pass. VM smoke tests pending. CI package workflows are being consolidated by compatibility baseline on `dev` before final promotion to `main`.
