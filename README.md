# 🐧 ProtonDrive Linux

An unofficial desktop app for Proton Drive on Linux. It gives you a native launcher for Proton Drive using Tauri, Rust, and Proton's official web app.

> This project is not affiliated with Proton AG.

## Status

**v1.2.0 — Working Beta**

ProtonDrive Linux supports login, CAPTCHA, two-factor authentication, Drive loading, file browsing, and downloading files to `~/Downloads`.

Available package formats:

| Format | Status | Best for |
|--------|--------|----------|
| AppImage | ✅ Available | Most Linux distributions |
| DEB | ✅ Available | Debian, Ubuntu, Linux Mint, and related distributions |
| RPM | ✅ Available | Fedora, RHEL, CentOS, and related distributions |
| AUR | ✅ Available | Arch, Manjaro, EndeavourOS, Garuda, and related distributions |
| Flatpak | ✅ Available | Local Flatpak installs |
| Snap | ✅ Available | Local Snap installs |

Download packages from the [Releases](https://github.com/DonnieDice/protondrive-linux/releases) page.

## Installation

### AppImage

The AppImage is the easiest option for most users.

```bash
chmod +x proton-drive_*.AppImage
./proton-drive_*.AppImage
```

### Debian / Ubuntu / Linux Mint

```bash
sudo apt install ./proton-drive_*.deb
```

### Fedora / RHEL / CentOS

```bash
sudo dnf install ./proton-drive-*.rpm
```

### Arch / Manjaro / EndeavourOS / Garuda

Install from the AUR:

```bash
yay -S proton-drive-bin
```

Or install a downloaded package directly:

```bash
sudo pacman -U proton-drive-bin-*.pkg.tar.zst
```

### Flatpak

```bash
flatpak install --user proton-drive.flatpak
flatpak run com.proton.drive
```

The Flatpak package is not currently available on Flathub. Download `proton-drive.flatpak` from the [Releases](https://github.com/DonnieDice/protondrive-linux/releases) page.

### Snap

```bash
sudo snap install --dangerous proton-drive_*.snap
```

The Snap package is not currently available in the Snap Store. Download it from the [Releases](https://github.com/DonnieDice/protondrive-linux/releases) page.

## Using the app

Open ProtonDrive Linux from your application launcher, then sign in with your Proton account. The app supports Proton login, CAPTCHA, two-factor authentication, and normal Proton Drive browsing.

Downloads are saved to your `~/Downloads` folder.

## Building from source

Most users should install a package from the [Releases](https://github.com/DonnieDice/protondrive-linux/releases) page instead. Build from source only if you want to test changes or package the app yourself.

### Requirements

- Node.js 18+
- Rust
- Git
- WebKitGTK and GTK development packages

Install system dependencies for your distribution:

```bash
# Fedora
sudo dnf install webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel openssl-devel

# Debian / Ubuntu
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev libssl-dev

# Arch / Manjaro
sudo pacman -S webkit2gtk-4.1 gtk3 libayatana-appindicator
```

### Build

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux

git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients

npm install
npm run build:web
npm run build:appimage
```

Built packages are created in `src-tauri/target/release/bundle/`.

For other package types, see the scripts in `scripts/` and the packaging notes in `docs/`.

## Troubleshooting

### Login error: "undefined is not a constructor"

This affected older builds. Upgrade to the latest release, or use the AppImage from the [Releases](https://github.com/DonnieDice/protondrive-linux/releases) page.

### White screen or crash on startup

Try launching the AppImage with WebKitGTK rendering workarounds:

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 ./proton-drive*.AppImage
```

This can help on some AMD/Wayland systems affected by WebKitGTK rendering bugs.

### Chunk loading error after login

Upgrade to the latest release. Older builds could fail while loading Proton web app assets after sign-in.

### Login refresh loop or CAPTCHA freeze

Upgrade to the latest release. Recent builds include fixes for Proton challenge and CAPTCHA flows.

### App stuck on the loading screen

- Check that your internet connection is working.
- Launch the app from a terminal to see error output.
- Open a GitHub issue and include the terminal log.

## How it works

ProtonDrive Linux wraps Proton Drive's official web frontend in a Tauri WebView. A local Rust layer helps the web app communicate with Proton's servers from the desktop environment.

Authentication, encryption, and file operations are handled by Proton's web app.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and contribution guidelines.

Technical packaging and compatibility notes are available in the [`docs/`](docs/) folder.

## License

AGPL-3.0 — see [LICENSE](LICENSE).
