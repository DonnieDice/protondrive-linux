# Patches Directory

Patches are organized by package type, then by distro/runtime target. Package workflows are intentionally separate, and each package owns its patch directory.

## Structure

```
patches/
├── common/            # Shared WebClients patches for ALL builds
├── appimage/
│   └── linux-baseline.patch
├── deb/
│   ├── debian.12.patch
│   ├── debian.13.patch
│   ├── ubuntu.24.04.patch
│   └── ubuntu.26.04.patch
├── rpm/
│   ├── fedora.43.patch
│   ├── fedora.44.patch
│   └── el10.patch
├── flatpak/
│   ├── org.gnome.Platform.49.patch
│   └── org.gnome.Platform.50.patch
├── snap/
│   ├── core24.patch
│   └── core26.patch
└── aur/                    # Arch Linux AUR-specific
```

## Architecture Rules

1. **Base code is universal.** `src-tauri/src/main.rs` must NOT contain distro-specific env vars (GDK_GL, LIBGL_ALWAYS_SOFTWARE, WEBKIT_DISABLE_*, etc.) or DISTRO_TYPE compile-time branching. The base binary ships clean.

2. **Distro/runtime-specific overrides go in `patches/<package>/<target>.patch`.** DEB/RPM targets are distro versions (for example `ubuntu.24.04` or `fedora.44`); AppImage/Flatpak/Snap targets are runtime names (for example `linux-baseline`, `org.gnome.Platform.49`, `core24`, or `core26`).

3. **Build scripts take or imply a patch target.** Local build scripts either default to their target or accept one as the first argument. CI workflows apply the matching patch via `DISTRO_PATCH`.

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
| AppImage | `scripts/appimage/build-local-appimage.sh` | `./scripts/appimage/build-local-appimage.sh --skip-webclient` | `appimage` |
| DEB Ubuntu 24.04 | `scripts/deb/build-local-deb.ubuntu.24.04.sh` | `./scripts/deb/build-local-deb.ubuntu.24.04.sh --skip-webclient` | `deb` |
| RPM Fedora 43 | `scripts/rpm/build-local-rpm.fedora.43.sh` | `./scripts/rpm/build-local-rpm.fedora.43.sh --skip-webclient` | `rpm` |
| RPM Fedora 44 | `scripts/rpm/build-local-rpm.fedora.44.sh` | `./scripts/rpm/build-local-rpm.fedora.44.sh --skip-webclient` | `rpm` |
| Flatpak GNOME 49 | `scripts/flatpak/build-local-flatpak.gnome49.sh` | `./scripts/flatpak/build-local-flatpak.gnome49.sh --skip-webclient` | `flatpak` |
| Flatpak GNOME 50 | `scripts/flatpak/build-local-flatpak.sh` | `./scripts/flatpak/build-local-flatpak.sh --skip-webclient` | `flatpak` |
| Snap core24 | `scripts/snap/build-local-snap.sh` | `./scripts/snap/build-local-snap.sh core24 --skip-webclient` | `snap` |
| Snap core26 | `scripts/snap/build-local-snap.sh` | `./scripts/snap/build-local-snap.sh core26 --skip-webclient` | `snap` |

## Current Patches

### common/
- `fix-tauri-worker-protocol.patch` - Disables Web Workers in Tauri environment (WebKitGTK doesn't support workers from tauri:// protocol)

### appimage/
- `linux-baseline.patch` - Portable AppImage baseline.

### deb/
- `debian.12.patch` - Debian-safe: GDK_GL=disable + LIBGL_ALWAYS_SOFTWARE
- `debian.13.patch` - Debian 13 WebKitGTK 2.46+ renderer settings
- `ubuntu.24.04.patch` - Ubuntu-safe: GDK_GL=software + LIBGL_ALWAYS_SOFTWARE=1 + JSC_useWasmIPInt=false
- `ubuntu.26.04.patch` - Ubuntu 26.04 WebKitGTK 2.48+ renderer settings + JSC_useWasmIPInt=false

### rpm/
- `fedora.43.patch` - Fedora 43 WebKitGTK 2.52+ sandbox/IPInt workaround
- `fedora.44.patch` - Fedora 44 WebKitGTK 2.52+ sandbox/IPInt workaround
- `el10.patch` - RHEL/Alma/Rocky/CentOS Stream 10 baseline

### flatpak/
- `org.gnome.Platform.49.patch` - GNOME 49 runtime + JSC_useWasmIPInt=false
- `org.gnome.Platform.50.patch` - GNOME 50 runtime + JSC_useWasmIPInt=false

### snap/
- `core24.patch` - Stable Snap base
- `core26.patch` - Experimental core26 base

## Adding New Patches

1. Create patch against git HEAD: `diff -u /tmp/main.rs.base /tmp/main.rs.patched > patches/<package>/<target>.patch`
2. Fix paths in the patch header: `--- a/src-tauri/src/main.rs` and `+++ b/src-tauri/src/main.rs`
3. Name the patch after the distro and version (e.g., `ubuntu.24.04.patch`, `fedora.40.patch`)
4. Test: `git apply --check patches/<package>/<distro>.<version>.patch`
5. Document why the patch is distro-specific in the commit message
