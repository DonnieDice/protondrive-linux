# Scripts Directory

Build scripts, utilities, and helper scripts for development and packaging. Release artifacts are built by the GitHub Actions workflows; local package scripts are primarily for debugging and reproducing workflow failures.

## Top-Level Scripts

| Script | Purpose |
|--------|---------|
| `build-webclients.sh` | Clone and build the Proton Drive web frontend from WebClients |
| `build-local-aur.sh` | Build AUR package locally |
| `build-local-deb.sh` | Compatibility wrapper for the primary DEB build |
| `build-local-flatpak.sh` | Compatibility wrapper for the primary Flatpak build |
| `build-local-snap.sh` | Compatibility wrapper for the primary Snap build |
| `build-local-appimage.sh` | Compatibility wrapper for the AppImage build |
| `ci/` | CI helper scripts |
| `create_stubs.py` | Stub private Proton npm packages for webpack builds |
| `fix_deps.py` | Fix dependency issues in WebClients |
| `setup-manjaro.sh` | Set up Manjaro build dependencies |

## Package Scripts

Each package type has its own subdirectory with local build scripts:

### `rpm/`

| Script | Target |
|--------|--------|
| `build-local-rpm.fedora.40.sh` | Fedora 40 (legacy) |
| `build-local-rpm.fedora.41.sh` | Fedora 41 (legacy) |
| `build-local-rpm.fedora.42.sh` | Fedora 42 (legacy) |
| `build-local-rpm.fedora.43.sh` | Fedora 43 |
| `build-local-rpm.fedora.44.sh` | Fedora 44 |

### `deb/`

| Script | Target |
|--------|--------|
| `build-local-deb.sh` | Debian/Ubuntu (configurable via DISTRO_TYPE) |
| `build-local-deb.ubuntu.22.04.sh` | Ubuntu 22.04 / Mint 21.x / Zorin 17 bundled-WebKit DEB |

### `appimage/`

| Script | Target |
|--------|--------|
| `build-local-appimage.sh` | Universal AppImage (linux-baseline) |

### `flatpak/`

| Script | Target |
|--------|--------|
| `build-local-flatpak.sh` | Flatpak (org.gnome.Platform//50) |
| `build-local-flatpak.gnome44.sh` | Flatpak (org.gnome.Platform//44, Ubuntu 22.04-compatible runtime) |

### `snap/`

| Script | Target |
|--------|--------|
| `build-local-snap.sh` | Snap core24 by default; pass `core22` for Ubuntu 22.04 or `core26` for the experimental core26 target |

## Usage

All local build scripts support `--skip-webclient` to skip the WebClients build if it's already done:

```bash
scripts/deb/build-local-deb.ubuntu.22.04.sh --skip-webclient
scripts/snap/build-local-snap.sh core22 --skip-webclient
```

## Related Documentation

- [Project README](../README.md)
- [Packaging docs](../docs/packaging.md)
- [Compatibility docs](../docs/compatibility.md)
- [Build and release docs](../docs/build-and-release.md)
