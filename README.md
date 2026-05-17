# ProtonDrive Linux

[![Latest Release](https://img.shields.io/github/v/release/DonnieDice/protondrive-linux?label=latest&color=brightgreen)](https://github.com/DonnieDice/protondrive-linux/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/DonnieDice/protondrive-linux/release.yml?branch=main&label=release%20CI)](https://github.com/DonnieDice/protondrive-linux/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](https://github.com/DonnieDice/protondrive-linux)
[![AUR](https://img.shields.io/aur/version/proton-drive?label=AUR&color=blue)](https://aur.archlinux.org/packages/proton-drive)

An unofficial desktop client for [Proton Drive](https://proton.me/drive) on Linux.

> **Disclaimer:** This project is not affiliated with, endorsed by, or connected to Proton AG. Proton Drive is a trademark of Proton AG. This is an independent community project that wraps the official Proton Drive web interface in a native Linux desktop window.

---

**Packages are not yet available on Flathub, Snap Store, or system repositories.** See the [Distribution Storefront Roadmap](#distribution-storefront-roadmap) for progress. For now, download from [Releases](https://github.com/DonnieDice/protondrive-linux/releases/latest).

---

## What You Get

- Desktop window for Proton Drive with system tray integration
- Login, CAPTCHA, and two-factor authentication support
- Proton Drive file browsing and downloads (saved to `~/Downloads`)
- Native packages for most major Linux distributions

## Supported Systems

| Format | Distributions |
|--------|---------------|
| **AppImage** | Any Linux with glibc 2.35+ (easiest option for most users) |
| **DEB** | Debian 12, Debian 13, Ubuntu 24.04, Ubuntu 26.04, Linux Mint 22.x |
| **RPM** | Fedora 43, Fedora 44, RHEL/CentOS/Alma/Rocky 10, openSUSE Tumbleweed |
| **AUR** | Arch, Manjaro, EndeavourOS, Garuda |
| **Flatpak** | GNOME Platform 49, GNOME Platform 50 |
| **Snap** | core24, core26 |
| **APK** | Alpine 3.20, Alpine 3.22 (musl) |

All packages are `x86_64`. See [docs/packaging.md](docs/packaging.md) for full compatibility details and roadmap targets (openSUSE Leap 16, Alpine 3.23).

## Install

### AppImage

Download, make executable, and run — no installation required:

```bash
# Download from https://github.com/DonnieDice/protondrive-linux/releases/latest
chmod +x proton-drive_*.AppImage
./proton-drive_*.AppImage
```

### Debian / Ubuntu / Linux Mint

```bash
# Download the .deb that matches your system from Releases, then:
sudo apt install ./proton-drive_*.deb
```

| Package | For |
|---------|-----|
| `proton-drive_*_ubuntu24.04_amd64.deb` | Ubuntu 24.04, Linux Mint 22.x, Ubuntu derivatives |
| `proton-drive_*_ubuntu26.04_amd64.deb` | Ubuntu 26.04 and derivatives |
| `proton-drive_*_debian12_amd64.deb` | Debian 12 |
| `proton-drive_*_debian13_amd64.deb` | Debian 13 |

### Fedora / RHEL / openSUSE

```bash
# Download the .rpm that matches your system from Releases, then:
sudo dnf install ./proton-drive-*.rpm
```

| Package | For |
|---------|-----|
| `proton-drive-*~fedora43.x86_64.rpm` | Fedora 43 |
| `proton-drive-*~fedora44.x86_64.rpm` | Fedora 44 |
| `proton-drive-*~el10.x86_64.rpm` | RHEL 10, CentOS Stream 10, Alma 10, Rocky 10 |
| `proton-drive-*-opensuse-tumbleweed.x86_64.rpm` | openSUSE Tumbleweed |

openSUSE Leap 16 users: use the AppImage until the Leap 16 RPM is released.

### Arch / Manjaro / EndeavourOS / Garuda

Install from the AUR:

```bash
yay -S proton-drive
```

Or install a downloaded package directly:

```bash
sudo pacman -U proton-drive-*.pkg.tar.zst
```

### Flatpak

```bash
# Download the .flatpak from Releases, then:
flatpak install --user proton-drive_*.flatpak
flatpak run com.proton.drive
```

Not yet on Flathub — see the [roadmap](#distribution-storefront-roadmap).

### Snap

```bash
# Download the .snap from Releases, then:
sudo snap install --dangerous proton-drive_*_core24_amd64.snap
```

Not yet in the Snap Store — see the [roadmap](#distribution-storefront-roadmap).

### Alpine

```bash
# Download the APK tarball from Releases, then:
tar -C / -xzf proton-drive_*_alpine3.20_x86_64.tar.gz
```

Alpine 3.20 and 3.22 are release-gated. Alpine 3.23 is a roadmap target. glibc DEB/RPM/AppImage packages are not compatible with Alpine/musl.

## Troubleshooting

### White Screen or Startup Crash

Try launching with WebKitGTK rendering workarounds:

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 ./proton-drive*.AppImage
```

This helps on some AMD/Wayland systems affected by WebKitGTK rendering bugs.

### Login Error, Chunk Loading Error, or CAPTCHA Freeze

Upgrade to the latest release — these are fixed in current builds.

### App Stuck on the Loading Screen

- Check your internet connection
- Launch from a terminal to see error output
- [Open an issue](https://github.com/DonnieDice/protondrive-linux/issues/new) with the terminal log

## Distribution Storefront Roadmap

Packages are currently GitHub release artifacts only. The goal is to publish
through native distribution storefronts so users can install and update
ProtonDrive Linux through their system package manager. Track progress in
[Issue #75](https://github.com/DonnieDice/protondrive-linux/issues/75).

| Storefront | Status | What's needed |
|------------|--------|---------------|
| **AUR** | Published | Already live at [aur.archlinux.org/packages/proton-drive](https://aur.archlinux.org/packages/proton-drive); auto-published via CI |
| **Flathub** | Not started | Flathub submission, sandbox review, app ID verification |
| **Snap Store** | Not started | Snap Store publisher account, `snapcraft register`, stable channel release |
| **COPR** (Fedora) | Not started | COPR project creation, spec file review, Fedora packaging guidelines |
| **PPA** (Ubuntu) | Not started | Launchpad PPA creation, GPG key, Debian source package format |
| **OBS** (openSUSE) | Not started | openSUSE Build Service project, spec/kiwi file, repository publishing |

## Building from Source

Most users should [download a release package](https://github.com/DonnieDice/protondrive-linux/releases/latest). Build from source only if you want to test changes or package the app yourself. Full build and packaging details are in [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

### Quick Build

Requirements: Node.js 20+, Rust, Git, WebKitGTK 4.1 + GTK 3 dev packages.

```bash
# Install system dependencies (example for Fedora):
sudo dnf install webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel openssl-devel

git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients
npm install
npm run build:web
npm run build:appimage
```

Built packages go to `src-tauri/target/release/bundle/`.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for the
workflow guide and [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed
build, packaging, and development rules.

## License

AGPL-3.0 or later. See [LICENSE](LICENSE).
