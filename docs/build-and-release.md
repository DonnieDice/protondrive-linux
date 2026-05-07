# Build and Release

This project has local package builds and GitHub Actions release builds. Keep them aligned whenever build behavior changes.

## Local Build Commands

Build the web client only:

```bash
npm run build:web
```

Build DEB, RPM, and AppImage through Tauri:

```bash
npm run build
```

Build one bundle target:

```bash
npm run build:deb
npm run build:rpm
npm run build:appimage
```

Convenience Make targets map to the same scripts:

```bash
make build
make build-deb
make build-rpm
make build-appimage
```

## Build Outputs

Tauri writes package artifacts under:

```text
src-tauri/target/release/bundle/
```

Expected package directories include:

```text
appimage/
deb/
rpm/
```

Additional package formats are produced by dedicated scripts or workflows.

## CI Workflows

The main workflows are:

| Workflow | Purpose |
| --- | --- |
| `.github/workflows/build-linux-packages.yml` | Builds DEB, RPM, and AppImage artifacts |
| `.github/workflows/build-snap.yml` | Builds Snap artifact |
| `.github/workflows/build-flatpak.yml` | Builds Flatpak artifact |
| `.github/workflows/publish-aur.yml` | Publishes or prepares AUR package metadata |
| `.github/workflows/generate-package-specs.yml` | Generates package specifications |
| `.github/workflows/release.yml` | Waits for build workflows, downloads artifacts, creates GitHub release |

## CI Build Sequence

`build-linux-packages.yml` currently:

1. Runs in a Debian 12 container for GLIBC 2.36 compatibility.
2. Installs Linux build dependencies.
3. Installs Rust stable.
4. Uses Node.js 22.
5. Syncs versions from `package.json`.
6. Clones `ProtonMail/WebClients`.
7. Runs dependency patching.
8. Installs and builds WebClients.
9. Builds Account and Verify apps.
10. Copies Account and Verify into Drive dist.
11. Verifies asset paths.
12. Installs root Tauri dependencies.
13. Builds DEB and RPM through Tauri.
14. Builds AppImage manually as a workaround for linuxdeploy/container issues.
15. Uploads artifacts.

## Release Sequence

`release.yml`:

1. Determines the release tag.
2. Creates and pushes the tag if needed.
3. Waits for Linux, Snap, and Flatpak build workflows.
4. Downloads successful artifacts.
5. Generates `SHA256SUMS`.
6. Creates GitHub release notes.
7. Publishes the GitHub release.

## Version Source of Truth

The source version is:

```text
package.json
```

Run this after changing it:

```bash
scripts/sync-version.sh
```

CI also syncs:

- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`

## GLIBC Compatibility

The Linux package workflow builds inside Debian 12 to keep the binary compatible with GLIBC 2.36. The workflow checks the compiled binary with `objdump` and fails if a newer GLIBC requirement appears.

## AppImage Notes

The workflow builds AppImage manually:

- Creates an `AppDir`.
- Copies the compiled `proton-drive` binary.
- Writes freedesktop desktop metadata.
- Copies icons using the app identifier `com.proton.drive`.
- Writes an `AppRun` with WebKitGTK environment fixes.
- Uses extracted `appimagetool` because FUSE is not available in the container.

Local `npm run build:appimage` uses Tauri's AppImage bundler path and may not match the manual CI workflow exactly.
