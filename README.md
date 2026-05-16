# ProtonDrive Linux

An unofficial desktop app for Proton Drive on Linux.

> This project is not affiliated with Proton AG.

## Download

Download the latest release from the
[Releases](https://github.com/DonnieDice/protondrive-linux/releases) page.

Packages are distributed as GitHub release artifacts. There is no apt
repository, Flathub listing, or Snap Store listing at this time.

## Current Release Support

Current release artifacts are `x86_64`.

| Format | Release-gated targets |
|--------|-----------------------|
| AppImage | portable glibc baseline |
| DEB | Debian 12, Debian 13, Ubuntu 24.04, Ubuntu 26.04 |
| RPM | Fedora 43, Fedora 44, RHEL/CentOS/Alma/Rocky 10, openSUSE Tumbleweed |
| AUR | Arch, Manjaro, EndeavourOS, Garuda |
| Flatpak | GNOME Platform 49, GNOME Platform 50 |
| Snap | core24, core26 |

Roadmap patch-ready targets are openSUSE Leap 16, Alpine
3.22, and Alpine 3.23. They are not release artifacts yet. See
[`docs/packaging.md`](docs/packaging.md).

## Installation

### AppImage

The AppImage is the easiest option for most users: download, make executable,
and run.

```bash
chmod +x proton-drive_*.AppImage
./proton-drive_*.AppImage
```

### Debian / Ubuntu / Linux Mint

Choose the DEB that matches your system:

| Package | For |
|---------|-----|
| `proton-drive_*_ubuntu24.04_amd64.deb` | Ubuntu 24.04, Linux Mint 22.x, matching Ubuntu-based derivatives |
| `proton-drive_*_ubuntu26.04_amd64.deb` | Ubuntu 26.04 and matching Ubuntu-based derivatives |
| `proton-drive_*_debian12_amd64.deb` | Debian 12 |
| `proton-drive_*_debian13_amd64.deb` | Debian 13 |

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
| `proton-drive-*-opensuse-tumbleweed.x86_64.rpm` | openSUSE Tumbleweed |

```bash
sudo dnf install ./proton-drive-*.rpm
```

openSUSE Leap 16 RPM is a roadmap target. Use the
AppImage on Leap 16 until the RPM workflow and smoke test are added.

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

Not currently available on Flathub. Download the `.flatpak` artifact from
[Releases](https://github.com/DonnieDice/protondrive-linux/releases) and install
it locally. Flatpak releases target the GNOME Platform runtime because the app
is GTK/WebKitGTK-based.

### Snap

```bash
sudo snap install --dangerous proton-drive_*_core24_amd64.snap
```

Not currently available in the Snap Store. Download the `.snap` artifact from
[Releases](https://github.com/DonnieDice/protondrive-linux/releases) and install
it locally with `--dangerous`.

### Alpine

Alpine APK packages are roadmap targets. Current glibc DEB/RPM/AppImage
artifacts are not Alpine/musl packages.

## Using The App

Open ProtonDrive Linux from your application launcher, then sign in with your
Proton account. The app supports login, CAPTCHA, two-factor authentication, and
normal Proton Drive browsing.

Downloads are saved to `~/Downloads`.

## Troubleshooting

### White Screen Or Startup Crash

Try launching with WebKitGTK rendering workarounds:

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 ./proton-drive*.AppImage
```

This can help on some AMD/Wayland systems affected by WebKitGTK rendering bugs.

### Login Error, Chunk Loading Error, Or CAPTCHA Freeze

Upgrade to the latest release; these issues are fixed in current builds.

### App Stuck On The Loading Screen

- Check that your internet connection is working.
- Launch the app from a terminal to see error output.
- Open a GitHub issue and include the terminal log.

## Building From Source

Most users should download a package from
[Releases](https://github.com/DonnieDice/protondrive-linux/releases). Build from
source only if you want to test changes or package the app yourself.

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

Built packages go to `src-tauri/target/release/bundle/`. Release artifacts are
produced by the package workflows documented in `docs/`.

## How It Works

ProtonDrive Linux wraps Proton Drive's official web frontend in a Tauri WebView.
A local Rust layer helps the web app communicate with Proton's servers from the
desktop environment. Authentication, encryption, and file operations are handled
by Proton's web app.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for
guidelines. Technical packaging and compatibility notes are in [`docs/`](docs/).

## License

AGPL-3.0. See [LICENSE](LICENSE).
