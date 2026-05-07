# ProtonDrive Linux Task List

Last updated: 2026-05-07

This repo currently ships the Tauri/WebKitGTK Proton Drive desktop wrapper. The immediate release target is v1.1.4 with validated Fedora/RPM login, CAPTCHA, 2FA, app selection, and Drive launch.

## Release Policy

- Push active fixes to `dev` first.
- Do not use `main` for test builds.
- Promote `dev` to `main` only after required package workflows are green.
- Create stable release tags from `main`.
- Keep distro-specific build behavior in that distro's workflow and patch directory.

## Current Release Gate

Required before promoting to `main`:

- [ ] `Build RPM` passes on `dev`
- [ ] `Build DEB` passes on `dev`
- [ ] `Build AppImage` passes on `dev`
- [x] `Build AUR` metadata validation passes on `dev`
- [x] `Generate Package Specs` passes on `dev`
- [x] Snap and Flatpak removed from the required release gate until restored
- [x] Fedora/RPM local install and launch validated
- [x] Login, CAPTCHA, 2FA, app selection, and Drive loading validated locally

## Workflow Work

- [x] Split native package builds into separate workflows:
  - `build-rpm.yml`
  - `build-deb.yml`
  - `build-appimage.yml`
  - `build-aur.yml`
- [x] Remove the combined `build-linux-packages.yml` workflow.
- [x] Keep release workflow waiting on RPM, DEB, and AppImage only.
- [ ] Fix any CI-only WebClients dependency/stub issues.
- [ ] Confirm release workflow downloads split artifacts correctly.
- [ ] Reintroduce Flatpak as a separate non-blocking workflow.
- [ ] Reintroduce Snap as a separate non-blocking workflow.

## Patch Ownership

- [x] `patches/common/` for source changes required by every package.
- [x] `patches/rpm/` for Fedora/RHEL/RPM-only changes.
- [x] `patches/deb/` for Debian/Ubuntu-only changes.
- [x] `patches/appimage/` for AppImage-only changes.
- [x] `patches/aur/` for Arch/AUR-only changes.
- [x] `patches/flatpak/` reserved for Flatpak-specific changes.
- [x] `patches/snap/` reserved for Snap-specific changes.
- [ ] Move any future distro-only behavior out of common code.

## Known Follow-Ups

- [ ] Test DEB on Ubuntu VM.
- [ ] Test AppImage on Ubuntu VM.
- [ ] Fix and validate AUR publishing after native artifacts are green.
- [ ] Review PR #38 after the current build/release path is stable.
- [ ] Decide whether a Rust SDK fork is useful after reviewing Proton's official SDK direction.
- [ ] Clean up archived Go/Fyne docs so they are clearly historical.

## Done In v1.1.4 Work

- [x] Disabled Webpack SRI for Drive, Account, and Verify builds.
- [x] Fixed nested Account and Verify asset paths.
- [x] Fixed Account lazy chunk public path.
- [x] Blocked `/api/` document navigations that caused login refresh loops.
- [x] Fixed CAPTCHA token handoff from external verification page back to Account.
- [x] Avoided Tauri IPC/console forwarding errors on external pages.
- [x] Organized debugging docs under `docs/debugging/`.
