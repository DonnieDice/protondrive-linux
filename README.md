# ProtonDrive Linux

An unofficial desktop app for Proton Drive on Linux.

> This project is not affiliated with Proton AG.

## Download

**v1.3.0**

Download the latest release from the [Releases](https://github.com/DonnieDice/protondrive-linux/releases) page.

Packages are distributed as GitHub release artifacts. There is no apt repository, Flathub listing, or Snap Store listing at this time.

| Format | Best for |
|--------|----------|
| AppImage | Most Linux distributions (portable, no install needed) |
| DEB | Debian, Ubuntu, Linux Mint, Zorin, Pop!\_OS |
| RPM | Fedora 43/44 and RHEL/CentOS/Alma/Rocky 10 |
| AUR | Arch, Manjaro, EndeavourOS, Garuda |
| Flatpak | Flatpak sandbox installs |
| Snap | Snap installs |

## Installation

### AppImage

The AppImage is the easiest option for most users — just download, make executable, and run.

```bash
chmod +x proton-drive_*.AppImage
./proton-drive_*.AppImage
```

### Debian / Ubuntu / Linux Mint

Choose the DEB that matches your system:

| Package | For |
|---------|-----|
| `proton-drive_*_ubuntu2204_bundled_amd64.deb` | Ubuntu 22.04, Linux Mint 21.x, Zorin 17, Pop!\_OS 22.04 |
| `proton-drive_*_ubuntu24.04_amd64.deb` | Ubuntu 24.04, Linux Mint 22.x |
| `proton-drive_*_ubuntu26.04_amd64.deb` | Ubuntu 26.04 |
| `proton-drive_*_debian12_amd64.deb` | Debian 12 (Bookworm) |
| `proton-drive_*_debian13_amd64.deb` | Debian 13 (Trixie) |

```bash
sudo apt install ./proton-drive_*.deb
```

### Fedora / RHEL / CentOS / Alma / Rocky

Choose the RPM that matches your system:

| Package | For |
|---------|-----|
| `proton-drive-*~fedora43.x86_64.rpm` | Fedora 43 |
| `proton-drive-*~fedora44.x86_64.rpm` | Fedora 44 |
| `proton-drive-*~el10.x86_64.rpm` | RHEL 10, CentOS Stream 10, Alma 10, Rocky 10 |

```bash
sudo dnf install ./proton-drive-*.rpm
```

RHEL/Alma/Rocky/CentOS Stream 9 is not supported by the current native RPM because EL9 ships GLib 2.68 and the current Tauri/GTK stack requires GLib 2.70 or newer.

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
flatpak install --user proton-drive_*.flatpak
flatpak run com.proton.drive
```

Not currently available on Flathub. Download the `.flatpak` artifact from [Releases](https://github.com/DonnieDice/protondrive-linux/releases) and install it locally.

### Snap

```bash
sudo snap install --dangerous proton-drive_*_core24_amd64.snap
```

Not currently available in the Snap Store. Download the `.snap` artifact from [Releases](https://github.com/DonnieDice/protondrive-linux/releases) and install it locally with `--dangerous`.

## Using the app

Open ProtonDrive Linux from your application launcher, then sign in with your Proton account. The app supports login, CAPTCHA, two-factor authentication, and normal Proton Drive browsing.

Downloads are saved to `~/Downloads`.

## Troubleshooting

### White screen or crash on startup

Try launching with WebKitGTK rendering workarounds:

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 ./proton-drive*.AppImage
```

This can help on some AMD/Wayland systems affected by WebKitGTK rendering bugs.

### Login error, chunk loading error, or CAPTCHA freeze

Upgrade to the latest release — these issues are fixed in current builds.

### App stuck on the loading screen

- Check that your internet connection is working.
- Launch the app from a terminal to see error output.
- Open a GitHub issue and include the terminal log.

## Building from source

Most users should download a package from [Releases](https://github.com/DonnieDice/protondrive-linux/releases). Build from source only if you want to test changes or package the app yourself.

### Requirements

- Node.js 20+
- Rust
- Git
- WebKitGTK 4.1 and GTK 3 development packages

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

Built packages go to `src-tauri/target/release/bundle/`. For other package types, see `scripts/` and `docs/`.

## How it works

ProtonDrive Linux wraps Proton Drive's official web frontend in a Tauri WebView. A local Rust layer helps the web app communicate with Proton's servers from the desktop environment. Authentication, encryption, and file operations are handled by Proton's web app.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. Technical packaging and compatibility notes are in [`docs/`](docs/).

## License

AGPL-3.0 — see [LICENSE](LICENSE).
