# Scripts Directory

Build scripts, utilities, and helper scripts for development and packaging.

## Top-Level Scripts

| Script | Purpose |
|--------|---------|
| `build-webclients.sh` | Clone and build the Proton Drive web frontend from WebClients |
| `build-local-aur.sh` | Build AUR package locally |
| `build-local-deb.sh` | Build DEB package locally |
| `build-local-flatpak.sh` | Build Flatpak package locally |
| `build-local-snap.sh` | Build Snap package locally |
| `build-local-appimage.sh` | Build AppImage package locally |
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

### `appimage/`

| Script | Target |
|--------|--------|
| `build-local-appimage.sh` | Universal AppImage (linux-baseline) |

### `flatpak/`

| Script | Target |
|--------|--------|
| `build-local-flatpak.sh` | Flatpak (org.gnome.Platform//50) |

### `snap/`

| Script | Target |
|--------|--------|
| `build-local-snap.sh` | Snap (core24/core26) |

## Usage

All local build scripts support `--skip-webclient` to skip the WebClients build if it's already done:

```bash
scripts/rpm/build-local-rpm.fedora.43.sh --skip-webclient
```

## Related Documentation

- [Project README](../README.md)
- [Packaging docs](../docs/packaging.md)
- [Compatibility docs](../docs/compatibility.md)
- [Build and release docs](../docs/build-and-release.md)
