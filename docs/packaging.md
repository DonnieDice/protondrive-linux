# Packaging

Packaging is intentionally split by distro/package type. Each package owns its workflow and patch directory, even when some build steps are similar.

## Package Ownership

| Package | Workflow | Patch Directory | Distro Patches | Notes |
|---------|----------|-----------------|----------------|-------|
| RPM | `.github/workflows/build-rpm.fedora.40.yml` | `patches/rpm/` | `fedora.40.patch` | Fedora/RHEL/openSUSE package path. Fedora 40 is the current release gate; the Fedora 40 RPM has also been validated on Fedora 41. |
| DEB | `.github/workflows/build-deb.yml` | `patches/deb/` | `ubuntu.24.04.patch`, `debian.12.patch` | Debian/Ubuntu/Mint/Zorin package path. Ubuntu VM validation pending. |
| AppImage | `.github/workflows/build-appimage.yml` | `patches/appimage/` | `ubuntu.24.04.patch` | Portable Linux package with distro-adaptive AppRun. |
| Flatpak | `.github/workflows/build-flatpak.yml` | `patches/flatpak/` | `gnome.47.patch` | GNOME 47 runtime Flatpak package. |
| Snap | `.github/workflows/build-snap.yml` | `patches/snap/` | `ubuntu.24.04.patch` | core24 Snap package. |
| AUR | `.github/workflows/build-aur.yml` | `patches/aur/` | — | Validates `aur/PKGBUILD` and `.SRCINFO`. Publishing is separate. |

## Design Standards

- Keep package workflows separate so one distro failure is easy to isolate.
- Keep distro-specific patches out of `patches/common/`.
- Use `patches/common/` only for changes required by all packages.
- **Base code (`src-tauri/src/main.rs`) must NOT contain distro-specific env vars or DISTRO_TYPE branching.** The base binary ships clean. Distro overrides come from `patches/<package>/<distro>.<version>.patch`.
- Keep app code fixes in source, not package-specific patches.
- Keep Fedora/RPM launch behavior in RPM packaging or runtime wrapper config unless every package needs it.
- Do not keep long-term distro branches for routine packaging differences.
- Use `dev` for workflow/build iteration and `main` for release.
- **One patch per distro version per package type.** Name patches `<distro>.<version>.patch` (e.g., `ubuntu.24.04.patch`, `fedora.40.patch`). If a later Fedora release needs a different packaging fix, create a new `fedora.<release>.patch` plus matching workflow and local build script instead of renaming the validated one.

## Distro Patch Convention

Patches are named `<distro>.<version>.patch` inside the package directory:

```
patches/
├── appimage/ubuntu.24.04.patch  # Ubuntu 24.04 WebKit env vars (runtime OS detection)
├── deb/ubuntu.24.04.patch       # Ubuntu DEB: GDK_GL=software
├── deb/debian.12.patch          # Debian DEB: GDK_GL=disable
├── rpm/fedora.40.patch          # Fedora RPM: GDK_GL=disable
├── flatpak/gnome.46.patch       # Flatpak GNOME 46 runtime
└── snap/ubuntu.24.04.patch      # Snap core24
```

Local build scripts are version-specific and line up with the workflow and patch names (e.g., `./scripts/rpm/build-local-rpm.fedora.40.sh`). CI workflows apply the matching patch via `DISTRO_PATCH` before `cargo build`.

Validated RPM compatibility currently includes:

- Fedora 40 local and remote RPM builds
- Fedora 41 install and login smoke tests using the Fedora 40 RPM artifact

## Required Runtime Fixes

The current Tauri/WebKitGTK app requires:

- WebKitGTK 4.1 dependencies.
- `WEBKIT_DISABLE_DMABUF_RENDERER=1` (all distros).
- `WEBKIT_DISABLE_COMPOSITING_MODE=1` (all distros).
- **Ubuntu 24.04+:** `GDK_GL=software` (NOT `GDK_GL=disable` — crashes WebKitWebProcess).
- **Debian/Fedora/others:** `GDK_GL=disable` + `LIBGL_ALWAYS_SOFTWARE=1`.
- Account and Verify nested asset path fixes.
- Webpack SRI disabled at build time for Drive, Account, and Verify.

## DISTRO_TYPE

Each build sets the `DISTRO_TYPE` env var at compile time so Rust code can use `option_env!("DISTRO_TYPE")` for package-specific behavior:

| DISTRO_TYPE | Used by | Worker behavior |
|-------------|---------|-----------------|
| `appimage` | AppImage | Native Workers (bundled WebKitGTK) |
| `deb` | DEB | Main-thread crypto (system WebKitGTK) |
| `rpm` | RPM | Main-thread crypto (system WebKitGTK) |
| `flatpak` | Flatpak | Main-thread crypto (sandboxed WebKitGTK) |
| `snap` | Snap | Main-thread crypto (sandboxed WebKitGTK) |

## Artifacts

Required release artifacts:

- `proton-drive-*.rpm`
- `proton-drive_*.deb`
- `proton-drive_*.AppImage`
- `SHA256SUMS`

AUR uses the AppImage release asset as its source package input.