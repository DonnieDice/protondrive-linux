# Patches Directory

Patches are organized by package type. Build scripts apply patches from `common/` first, then package-specific patches.

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

## Build Scripts (Local)

Each package type has a corresponding local build script:

| Package | Local Script | Workflow |
|---------|--------------|----------|
| AUR | `scripts/build-local-aur.sh` | `publish-aur.yml` |
| AppImage | `scripts/build-local-appimage.sh` | `build-appimage.yml` |
| DEB | `scripts/build-local-deb.sh` | `build-deb.yml` |
| RPM | `scripts/build-local-rpm.sh` | `build-rpm.yml` |
| Flatpak | `scripts/build-local-flatpak.sh` | `build-flatpak.yml` |
| Snap | `scripts/build-local-snap.sh` | `build-snap.yml` |

## Current Patches

### common/
- `fix-tauri-worker-protocol.patch` - Disables Web Workers in Tauri environment (WebKitGTK doesn't support workers from tauri:// protocol)

## Adding New Patches

1. Create patch: `git diff > patches/<type>/descriptive-name.patch`
2. Use descriptive kebab-case names
3. Place in `common/` if needed for all builds, otherwise in specific package dir
