<div align="center">

# ProtonDrive Linux

An unofficial desktop client for [Proton Drive](https://proton.me/drive) on Linux.

[![GitHub release](https://img.shields.io/github/v/release/DonnieDice/protondrive-linux?label=latest&color=brightgreen)](https://github.com/DonnieDice/protondrive-linux/releases/latest)
[![Release CI](https://img.shields.io/github/actions/workflow/status/DonnieDice/protondrive-linux/release.yml?branch=main&label=CI)](https://github.com/DonnieDice/protondrive-linux/actions/workflows/release.yml)
[![AUR](https://img.shields.io/aur/version/proton-drive?color=blue)](https://aur.archlinux.org/packages/proton-drive)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](./LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/DonnieDice/protondrive-linux?style=social)](https://github.com/DonnieDice/protondrive-linux/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/DonnieDice/protondrive-linux?style=social)](https://github.com/DonnieDice/protondrive-linux/fork)
[![Platform](https://img.shields.io/badge/platform-Linux-ffb86c)](https://github.com/DonnieDice/protondrive-linux/releases/latest)
[![Architecture](https://img.shields.io/badge/arch-x86__64-ff79c6)](https://github.com/DonnieDice/protondrive-linux/releases/latest)
[![Tauri](https://img.shields.io/badge/built%20with-Tauri-24c8d8)](https://tauri.app/)
[![Rust](https://img.shields.io/badge/written%20in-Rust-dea584)](https://www.rust-lang.org/)

> **Disclaimer:** This project is not affiliated with, endorsed by, or connected to Proton AG.
> Proton Drive is a trademark of Proton AG. This is an independent community project.

</div>

---

## About

ProtonDrive Linux wraps the official [Proton Drive](https://proton.me/drive) web interface in a native Linux desktop window using [Tauri](https://tauri.app/) and [WebKitGTK](https://webkitgtk.org/). Authentication, encryption, and file operations are handled by Proton's web app — this project provides the native shell, system tray integration, and cross-distro packaging.

**Features:**

- Desktop window for Proton Drive with system tray integration
- Login, CAPTCHA, and two-factor authentication support
- Proton Drive file browsing and downloads (saved to `~/Downloads`)
- Native packages for most major Linux distributions
- Built with Rust + Tauri for a small footprint and low resource usage

> **Packages are not yet available on Flathub, Snap Store, or system repositories.** For now, download from [Releases](https://github.com/DonnieDice/protondrive-linux/releases/latest).

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow guide and [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed build, packaging, and development rules.

## License

AGPL-3.0 or later. See [LICENSE](LICENSE).
