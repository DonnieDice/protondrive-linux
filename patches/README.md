# Patches Directory

Patches are organized by package type. Package workflows are intentionally separate, and each package owns its patch directory.

## Structure

```
patches/
├── common/          # Shared patches for ALL builds
├── aur/             # Arch Linux AUR-specific
├── appimage/        # AppImage-specific
├── deb/             # Debian/Ubuntu-specific
├── rpm/             # Fedora/RHEL-specific
├── flatpak/         # Flatpak-specific
└── snap/            # Snap-specific
```

## Ownership Rule

- Put patches in `common/` only when every package needs the same WebClients source change.
- Put distro/package-specific behavior in that package directory.
- Do not add Fedora/RPM-only fixes to `deb/`, `appimage/`, or `common/`.
- Do not use long-term distro branches for packaging differences.

## Build Scripts (Local)

Each package type has a corresponding local build script:

| Package | Local Script | Workflow |
|---------|--------------|----------|
| AUR | `aur/PKGBUILD` validation | `build-aur.yml` |
| AppImage | `scripts/build-local-appimage.sh` | `build-appimage.yml` |
| DEB | `scripts/build-local-deb.sh` | `build-deb.yml` |
| RPM | `scripts/build-local-rpm.sh` | `build-rpm.yml` |
| Flatpak | `scripts/build-local-flatpak.sh` | deferred |
| Snap | `scripts/build-local-snap.sh` | deferred |

## Current Patches

### common/
- `fix-tauri-worker-protocol.patch` - Disables Web Workers in Tauri environment (WebKitGTK doesn't support workers from tauri:// protocol)

## Adding New Patches

1. Create patch: `git diff > patches/<type>/descriptive-name.patch`
2. Use descriptive kebab-case names
3. Place in `common/` if needed for all builds, otherwise in specific package dir
4. Document why the patch is package-specific in the commit message
