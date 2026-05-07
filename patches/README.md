# Patches Directory

Patches are organized by package type, then by distro. Package workflows are intentionally separate, and each package owns its patch directory.

## Structure

```
patches/
├── common/           # Shared patches for ALL builds
├── appimage/
│   ├── ubuntu.patch  # AppImage on Ubuntu (runtime OS detection, GDK_GL=software)
│   └── fedora.patch  # AppImage on Fedora (full software fallback)
├── deb/
│   ├── ubuntu.patch  # DEB on Ubuntu (GDK_GL=software)
│   └── debian.patch  # DEB on Debian (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
├── rpm/
│   └── fedora.patch  # RPM on Fedora (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
├── flatpak/
│   └── gnome.patch   # Flatpak on GNOME runtime (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
├── snap/
│   └── core24.patch  # Snap on core24 (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
└── aur/              # Arch Linux AUR-specific
```

## Architecture Rules

1. **Base code is universal.** `src-tauri/src/main.rs` must NOT contain distro-specific env vars (GDK_GL, LIBGL_ALWAYS_SOFTWARE, WEBKIT_DISABLE_*, etc.) or DISTRO_TYPE compile-time branching. The base binary ships clean.

2. **Distro-specific overrides go in `patches/<package>/<distro>.patch`.** Each patch is named after the distro it targets (e.g., `ubuntu.patch`, `fedora.patch`, `debian.patch`).

3. **Build scripts auto-detect the distro.** Local build scripts (`build-local-*.sh`) read `/etc/os-release` and apply the matching `<distro>.patch`. CI workflows apply the patch explicitly.

4. **`DISTRO_TYPE` env var is set at build time.** Each workflow and build script exports `DISTRO_TYPE=appimage|deb|rpm|flatpak|snap` so the Rust code can use `option_env!("DISTRO_TYPE")` for package-specific behavior (like Worker init).

5. **`patches/common/` is for changes ALL packages need.** Never put distro-specific fixes here.

6. **One patch per distro per package type.** Do not split a distro's changes across multiple patch files. Merge them into a single `<distro>.patch`.

## Ownership Rule

- Put patches in `common/` only when every package needs the same WebClients source change.
- Put distro/package-specific behavior in that package directory under `<distro>.patch`.
- Do not add Fedora/RPM-only fixes to `deb/`, `appimage/`, or `common/`.
- Do not use long-term distro branches for packaging differences.

## Build Scripts (Local)

Each package type has a corresponding local build script that auto-detects the distro and applies the right patch:

| Package | Local Script | Workflow | DISTRO_TYPE |
|---------|--------------|----------|-------------|
| AppImage | `scripts/build-local-appimage.sh` | `build-appimage.yml` | `appimage` |
| DEB | `scripts/build-local-deb.sh` | `build-deb.yml` | `deb` |
| RPM | `scripts/build-local-rpm.sh` | `build-rpm.yml` | `rpm` |
| Flatpak | `scripts/build-local-flatpak.sh` | `build-flatpak.yml` | `flatpak` |
| Snap | `scripts/build-local-snap.sh` | `build-snap.yml` | `snap` |
| AUR | `aur/PKGBUILD` validation | `build-aur.yml` | `aur` |

## Current Patches

### common/
- `fix-tauri-worker-protocol.patch` - Disables Web Workers in Tauri environment (WebKitGTK doesn't support workers from tauri:// protocol)

### appimage/
- `ubuntu.patch` - Runtime OS detection: GDK_GL=software on Ubuntu, GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE on Debian/Fedora
- `fedora.patch` - Full software fallback: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### deb/
- `ubuntu.patch` - Ubuntu-safe: GDK_GL=software (avoids WebKitWebProcess crash)
- `debian.patch` - Debian-safe: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### rpm/
- `fedora.patch` - Fedora-safe: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### flatpak/
- `gnome.patch` - GNOME runtime: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### snap/
- `core24.patch` - core24 runtime: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

## Adding New Patches

1. Create patch against git HEAD: `diff -u /tmp/main.rs.base /tmp/main.rs.patched > patches/<package>/<distro>.patch`
2. Fix paths in the patch header: `--- a/src-tauri/src/main.rs` and `+++ b/src-tauri/src/main.rs`
3. Name the patch after the distro (e.g., `ubuntu.patch`, `fedora.patch`, `debian.patch`)
4. Test: `git apply --check patches/<package>/<distro>.patch`
5. Document why the patch is distro-specific in the commit message
