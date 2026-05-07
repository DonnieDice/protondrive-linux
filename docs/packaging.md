# Packaging

Packaging must preserve one shared application behavior across all Linux formats. Package-specific differences should live in packaging metadata, build scripts, environment setup, or CI workflow logic.

## Supported Package Formats

Current repository automation covers:

- DEB
- RPM
- AppImage
- Snap
- Flatpak
- AUR metadata/publication flow

Do not assume a package is published to a public store unless the corresponding release or store listing exists. The repository can build artifacts even when they are intended for manual installation.

## Tauri Bundle Targets

`src-tauri/tauri.conf.json` enables:

```json
"targets": ["deb", "rpm", "appimage"]
```

Snap, Flatpak, and AUR are handled outside the primary Tauri bundle target list.

## App Identity

Important identifiers:

| Field | Value |
| --- | --- |
| Product name | `Proton Drive` |
| Tauri identifier | `com.proton.drive` |
| Binary name | `proton-drive` |
| Cargo package | `proton-drive` |

Keep desktop files, icons, bundle metadata, and package scripts aligned with those values.

## Desktop Files

Desktop metadata lives in:

```text
src-tauri/linux/com.proton.drive.desktop
src-tauri/linux/proton-drive.desktop
```

CI copies `com.proton.drive.desktop` to `proton-drive.desktop` before bundling for Tauri compatibility.

## Linux Runtime Dependencies

Configured package dependencies include:

DEB:

```text
libwebkit2gtk-4.1-0
libgtk-3-0
libayatana-appindicator3-1
gstreamer1.0-plugins-base
gstreamer1.0-plugins-good
```

RPM:

```text
webkit2gtk4.1
gtk3
libayatana-appindicator-gtk3
```

Build-time dependencies are broader and are installed in CI workflows.

## Worker Behavior by Package

The injected script uses `DISTRO_TYPE` at compile time to choose worker behavior:

| `DISTRO_TYPE` | Behavior |
| --- | --- |
| `appimage` | Native Workers |
| `aur` | Native Workers |
| `deb` | Workers disabled, main-thread crypto fallback |
| `rpm` | Workers disabled, main-thread crypto fallback |
| `flatpak` | Workers disabled, main-thread crypto fallback |
| `snap` | Workers disabled, main-thread crypto fallback |
| unset | Workers disabled, main-thread crypto fallback |

If package scripts compile the app with a specific `DISTRO_TYPE`, make sure the selected behavior is tested on that package format.

## Package-Specific Scripts

Local package helpers:

```text
scripts/build-local-aur.sh
scripts/build-local-appimage.sh
scripts/build-local-deb.sh
scripts/build-local-flatpak.sh
scripts/build-local-rpm.sh
scripts/build-local-snap.sh
```

Release helper:

```text
scripts/build-and-release.sh
```

When changing core build behavior, inspect these scripts and the corresponding `.github/workflows/*.yml` files together.

## Patch Placement

Use:

```text
patches/common/
```

for WebClients changes required by every package format.

Use package-specific patch directories only for packaging/runtime issues that cannot be solved globally.

## Installation Examples

Install a local DEB:

```bash
sudo apt install ./proton-drive_*.deb
```

Install a local RPM:

```bash
sudo dnf install ./proton-drive-*.rpm
```

Run AppImage:

```bash
chmod +x proton-drive_*.AppImage
./proton-drive_*.AppImage
```

Install a local Snap:

```bash
sudo snap install --dangerous proton-drive_*.snap
```

Install a local Flatpak bundle:

```bash
flatpak install --user proton-drive.flatpak
```
