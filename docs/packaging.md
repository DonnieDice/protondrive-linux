# Packaging

Packaging is intentionally split by distro/package type. Each package owns its workflow and patch directory, even when some build steps are similar.

## Package Ownership

| Package | Workflow | Patch Directory | Notes |
|---------|----------|-----------------|-------|
| RPM | `.github/workflows/build-rpm.yml` | `patches/rpm/` | Fedora/RHEL/openSUSE package path. Fedora launch is locally validated. |
| DEB | `.github/workflows/build-deb.yml` | `patches/deb/` | Debian/Ubuntu/Mint/Zorin package path. Ubuntu VM validation pending. |
| AppImage | `.github/workflows/build-appimage.yml` | `patches/appimage/` | Portable Linux package path with AppRun WebKitGTK env fixes. |
| AUR | `.github/workflows/build-aur.yml` | `patches/aur/` | Validates `aur/PKGBUILD` and `.SRCINFO`. Publishing is separate. |
| Flatpak | deferred | `patches/flatpak/` | Restore after native packages are green. |
| Snap | deferred | `patches/snap/` | Restore after native packages are green. |

## Design Standards

- Keep package workflows separate so one distro failure is easy to isolate.
- Keep distro-specific patches out of `patches/common/`.
- Use `patches/common/` only for changes required by all packages.
- Keep app code fixes in source, not package-specific patches.
- Keep Fedora/RPM launch behavior in RPM packaging or runtime wrapper config unless every package needs it.
- Do not keep long-term distro branches for routine packaging differences.
- Use `dev` for workflow/build iteration and `main` for release.

## Required Runtime Fixes

The current Tauri/WebKitGTK app requires:

- WebKitGTK 4.1 dependencies.
- `WEBKIT_DISABLE_DMABUF_RENDERER=1`.
- `WEBKIT_DISABLE_COMPOSITING_MODE=1`.
- Account and Verify nested asset path fixes.
- Webpack SRI disabled at build time for Drive, Account, and Verify.

## Artifacts

Required release artifacts:

- `proton-drive-*.rpm`
- `proton-drive_*.deb`
- `proton-drive_*.AppImage`
- `SHA256SUMS`

AUR uses the AppImage release asset as its source package input.
