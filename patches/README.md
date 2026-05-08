# Patches Directory

Patches are organized by package type, then by distro version. Package workflows are intentionally separate, and each package owns its patch directory.

## Structure

```
patches/
├── common/            # Shared patches for ALL builds
├── appimage/
│   ├── ubuntu.24.04.patch  # AppImage on Ubuntu 24.04 (runtime OS detection, GDK_GL=software)
│   └── fedora.42.patch     # AppImage on Fedora 42 (full software fallback)
├── deb/
│   ├── ubuntu.24.04.patch  # DEB on Ubuntu 24.04 (GDK_GL=software)
│   └── debian.12.patch     # DEB on Debian 12 (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
├── rpm/
│   ├── fedora.40.patch     # RPM on Fedora 40 (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
│   └── fedora.42.patch     # RPM on Fedora 42 (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
├── flatpak/
│   └── gnome.46.patch      # Flatpak on GNOME 46 runtime (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
├── snap/
│   └── ubuntu.24.04.patch  # Snap on core24 (GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE)
└── aur/                    # Arch Linux AUR-specific
```

## Architecture Rules

1. **Base code is universal.** `src-tauri/src/main.rs` must NOT contain distro-specific env vars (GDK_GL, LIBGL_ALWAYS_SOFTWARE, WEBKIT_DISABLE_*, etc.) or DISTRO_TYPE compile-time branching. The base binary ships clean.

2. **Distro-specific overrides go in `patches/<package>/<distro>.<version>.patch`.** Each patch is named after the distro and version it targets (e.g., `ubuntu.24.04.patch`, `fedora.42.patch`, `debian.12.patch`).

3. **Build scripts take a patch argument.** Local build scripts (`build-local-*.sh`) require `<patch-name>` as the first argument (e.g., `ubuntu.24.04`). CI workflows apply the patch via `DISTRO_PATCH` variable (defaults to the primary distro for that package type).

4. **`DISTRO_TYPE` env var is set at build time.** Each workflow and build script exports `DISTRO_TYPE=appimage|deb|rpm|flatpak|snap` so the Rust code can use `option_env!("DISTRO_TYPE")` for package-specific behavior (like Worker init).

5. **`patches/common/` is for changes ALL packages need.** Never put distro-specific fixes here.

6. **One patch per distro version per package type.** Do not split a distro's changes across multiple patch files. Merge them into a single `<distro>.<version>.patch`.

## Ownership Rule

- Put patches in `common/` only when every package needs the same WebClients source change.
- Put distro/package-specific behavior in that package directory under `<distro>.<version>.patch`.
- Do not add Fedora/RPM-only fixes to `deb/`, `appimage/`, or `common/`.
- Do not use long-term distro branches for packaging differences.

## Build Scripts (Local)

Each package type has a corresponding local build script that takes a patch name argument:

| Package | Local Script | Usage | DISTRO_TYPE |
|---------|--------------|-------|-------------|
| AppImage | `scripts/build-local-appimage.sh` | `./scripts/build-local-appimage.sh ubuntu.24.04` | `appimage` |
| DEB | `scripts/build-local-deb.sh` | `./scripts/build-local-deb.sh ubuntu.24.04` | `deb` |
| RPM | `scripts/build-local-rpm.sh` | `./scripts/build-local-rpm.sh fedora.40` | `rpm` |
| Flatpak | `scripts/build-local-flatpak.sh` | `./scripts/build-local-flatpak.sh gnome.46` | `flatpak` |
| Snap | `scripts/build-local-snap.sh` | `./scripts/build-local-snap.sh ubuntu.24.04` | `snap` |

## Current Patches

### common/
- `fix-tauri-worker-protocol.patch` - Disables Web Workers in Tauri environment (WebKitGTK doesn't support workers from tauri:// protocol)

### appimage/
- `ubuntu.24.04.patch` - Runtime OS detection: GDK_GL=software on Ubuntu, GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE on Debian/Fedora
- `fedora.42.patch` - Full software fallback: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### deb/
- `ubuntu.24.04.patch` - Ubuntu-safe: GDK_GL=software (avoids WebKitWebProcess crash)
- `debian.12.patch` - Debian-safe: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### rpm/
- `fedora.40.patch` - Fedora-safe: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE
- `fedora.42.patch` - Fedora-safe: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### flatpak/
- `gnome.46.patch` - GNOME 46 runtime: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

### snap/
- `ubuntu.24.04.patch` - core24 runtime: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE

## Adding New Patches

1. Create patch against git HEAD: `diff -u /tmp/main.rs.base /tmp/main.rs.patched > patches/<package>/<distro>.<version>.patch`
2. Fix paths in the patch header: `--- a/src-tauri/src/main.rs` and `+++ b/src-tauri/src/main.rs`
3. Name the patch after the distro and version (e.g., `ubuntu.24.04.patch`, `fedora.42.patch`)
4. Test: `git apply --check patches/<package>/<distro>.<version>.patch`
5. Document why the patch is distro-specific in the commit message
