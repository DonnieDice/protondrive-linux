# Changelog

## Unreleased

### Added

- Merged build/release, compatibility, Linux ABI target, and packaging notes
  into `docs/packaging.md`.
- Patch-ready entries for openSUSE Tumbleweed, openSUSE Leap 16, Alpine 3.22,
  and Alpine 3.23.
- Roadmap patch-ready metadata in `packaging/compatibility-map.yml` for musl,
  openSUSE, legacy candidates, and architecture expansion.
- Documentation now uses the same support states everywhere: release-gated,
  roadmap patch-ready, legacy candidate, and not primary.
- Explicit release verification checklist in `docs/packaging.md`, with runtime
  smoke status mirrored in `packaging/compatibility-map.yml`.

### Changed

- Rewrote compatibility, packaging, patch, and release docs to separate the
  current 13-artifact release gate from roadmap patch-ready targets.
- Collapsed `docs/packaging.md` around one support matrix covering release
  artifacts, roadmap patch-ready targets, legacy candidates, and non-primary
  targets.
- Corrected compatibility-map build containers for Debian 13, Ubuntu 26.04, and
  EL10 to match the actual workflow container images.

## 1.3.0 - 2026-05-11

### Added

- DEB workflows for Debian 13 (`build-deb.debian.13.yml`) and Ubuntu 26.04 (`build-deb.ubuntu.26.04.yml`).
- RPM workflow for EL10 (`build-rpm.el10.yml`).
- Snap core26 workflow (`build-snap.core26.yml`) with `core26.patch` for webkit2gtk 2.52+ sandbox and IPInt fixes.
- Distro patches: `deb/debian.13.patch`, `deb/ubuntu.26.04.patch`, `rpm/el10.patch`, `snap/core26.patch`.
- WebKitGTK and runtime mapping entries in `packaging/compatibility-map.yml` for all new targets.
- Release workflow (`release.yml`) updated to download and attach all 13 build artifacts.

### Changed

- Removed Fedora 40, 41, and 42 workflows and patches (EOL or replaced by EL/F43+ baselines).
- Updated `docs/`, `README.md`, and `packaging.md` to reflect current workflow and patch inventory.
- Bumped version to 1.3.0.

## 1.2.0 - 2026-05-11

### Added

- Full CI pipeline for all package formats: AppImage, Flatpak, Snap, AUR, DEB, RPM (Fedora 40-44).
- Static `packaging/snap/snapcraft.yaml` template for Snap builds (version substituted at build time).
- `packaging/compatibility-map.yml` with runtime/ABI-based naming convention for all targets.

### Changed

- Restructured patches to runtime/ABI naming: `appimage/linux-baseline`, `aur/arch`, `flatpak/org.gnome.Platform.50`, `snap/core24`.
- Collapsed redundant per-distro Arch patches (manjaro, endeavour, garuda) into single `aur/arch.patch` + `aur/arch.wrapper`.
- AppImage uses single `linux-baseline` target (glibc compatibility boundary) instead of per-distro targets.
- Flatpak and Snap patches target the runtime (org.gnome.Platform.50, core24), not the host distro.
- DEB patches regenerated against current `main.rs` base code.
- Fixed Flatpak/Snap CI YAML parse errors by moving `DISTRO_PATCH` from top-level `env:` to step-level computation.
- Fixed Snap CI: install `snapcraft` via snap (not apt), use static snapcraft.yaml template.
- AUR CI now does full Tauri build + `makepkg` to produce real `.pkg.tar.zst` packages.
- Updated README, compatibility docs, and packaging docs for runtime/ABI naming convention.

### Removed

- Deleted redundant patches: `appimage/arch.patch`, `appimage/manjaro.patch`, `aur/manjaro.{patch,wrapper}`, `aur/endeavour.{patch,wrapper}`, `aur/garuda.{patch,wrapper}`, `flatpak/ubuntu.24.04.patch`, `snap/ubuntu.24.04.patch`.
- Deleted `docs/comprehensive-docs` branch (was a full Go rewrite, not documentation).

## 1.1.5 - 2026-05-07

### Fixed

- Fixed `package.json` build scripts to use Tauri 2.x `--bundles` flag instead of Tauri 1.x `-- --bundles` passthrough syntax.
- Added Node.js 20+ minimum version requirement (`engines` field + `prebuild` check) to prevent cryptic errors on old Node versions.
- Removed stale `WebClients-workflow-test` submodule reference; WebClients is cloned at build time only.

### Repository Cleanup

- Removed legacy build scripts: `test-build.sh`, `build-and-release.sh`, `setup.sh`, `sync-version.sh`.
- Removed obsolete Go-era documentation: `docs/architecture.md`, `docs/development.md`, `docs/webclients-analysis.md`, `docs/troubleshooting.md`, `docs/multi-agent-coordination.md`, `docs/phases/`, `docs/archive/`.
- Removed duplicate desktop entry `com.proton.drive.desktop` (kept `proton-drive.desktop`).
- Removed auto-generated `src-tauri/gen/schemas/` from tracking.
- Removed unused `snap/snapcraft.yaml.template`.
- Removed `yarn.lock` (project uses npm).
- Added `src-tauri/gen/` and `yarn.lock` to `.gitignore`.
- Cleaned up `Makefile` targets to match current scripts.

## 1.1.4 - 2026-05-07

### Fixed

- Stubbed private Proton packages (`@proton/proton-foundation-search`) to unblock CI webpack builds across RPM, DEB, and AppImage.
- Split monolithic `build-linux-packages.yml` into separate per-distro workflows (`build-rpm.yml`, `build-deb.yml`, `build-appimage.yml`, `build-aur.yml`).
- Removed stale Flatpak/Snap workflows from the required release gate.
- Added `tasks/`, `claude/`, `agents/` to `.gitignore` for AI tool state directories.
- Fixed `package.json` build scripts to use Tauri 2.x `--bundles` flag instead of Tauri 1.x `-- --bundles` passthrough syntax.
- Added Node.js 20+ minimum version requirement (`engines` field + `prebuild` check) to prevent `SyntaxError` and `styleText is not a function` errors on old Node versions.
- Removed `WebClients-workflow-test` submodule reference; WebClients is now cloned at build time only.

### CI

- All five required workflows (RPM, DEB, AppImage, AUR, Package Specs) pass green on `dev`.
- RPM, DEB, and AppImage artifact uploads confirmed.
- Release workflow waits for RPM, DEB, and AppImage builds then downloads and attaches artifacts.

### Repository Hygiene

- Package patch directories created under `patches/` for each distro type.
- Build and release documentation updated for split workflow architecture.

## 1.1.3 - 2026-05-07

### Fixed

- Fixed Fedora/RPM launch flow through login, CAPTCHA, 2FA, app selection, and Drive load.
- Fixed WebClient chunk loading after login by building Drive, Account, and Verify with `--no-sri` and keeping nested Account/Verify chunk paths relative.
- Fixed Account app reload loops by blocking `/api/` document navigations that should be handled by the fetch proxy.
- Fixed CAPTCHA completion by allowing internal `about:blank` captcha navigations and only returning to Account after an explicit verification-token callback.
- Fixed CAPTCHA auth retry by preserving credentials temporarily, carrying the verification token back to the local Account app, and adding Proton human-verification headers to the retried auth request.
- Reduced noisy Tauri ACL errors from external captcha pages by only forwarding console logs to Rust on local `tauri://` pages.

### Verified

- Fedora local release binary launched with `WEBKIT_DISABLE_DMABUF_RENDERER=1` and `WEBKIT_DISABLE_COMPOSITING_MODE=1`.
- Login screen rendered without refresh loop.
- CAPTCHA completed, 2FA prompt appeared, app selection loaded, and Drive opened successfully.

### Repository Hygiene

- Moved long debugging notes to `docs/debugging/worker-login-sri.md`.
- Cleaned agent guidance files and ignored local agent state directories.
- Kept application lockfiles tracked for reproducible release builds.

## 1.1.2 - 2026-05-07

### Fixed

- Fixed WebKit worker startup failures affecting RPM/DEB builds on Fedora and Ubuntu.
- Added WebKitGTK rendering environment flags for AMD/Wayland startup stability.
