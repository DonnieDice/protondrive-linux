<img width="28" src="src-tauri/icons/proton-drive.svg">&nbsp;&nbsp;ProtonDrive Linux
===============

[![latest](https://img.shields.io/github/v/release/DonnieDice/protondrive-linux?label=latest&color=6d4aff)](https://github.com/DonnieDice/protondrive-linux/releases/latest)
[![downloads](https://img.shields.io/github/downloads/DonnieDice/protondrive-linux/total?color=6d4aff)](https://github.com/DonnieDice/protondrive-linux/releases)
[![license](https://img.shields.io/badge/license-AGPL--3.0-6d4aff)](docs/LICENSE)
[![issues](https://img.shields.io/github/issues/DonnieDice/protondrive-linux?color=6d4aff)](https://github.com/DonnieDice/protondrive-linux/issues)

An unofficial desktop client for [Proton Drive](https://proton.me/drive) on Linux.

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

## Documentation

| | |
|---|---|
| [Contributing](docs/workflow.md) | Workflow guide |
| [Build & Packaging](docs/CONTRIBUTING.md) | Detailed dev, build, and packaging rules |
| [Packaging & Compatibility](docs/packaging.md) | Support matrix, compatibility gates, patch policy |
| [Changelog](docs/CHANGELOG.md) | Release history |
| [License](docs/LICENSE) | AGPL-3.0 or later |
| [Security Policy](docs/SECURITY.md) | Vulnerability reporting |
| [Code of Conduct](docs/CODE_OF_CONDUCT.md) | Community standards |

&nbsp;

> **Disclaimer:** This project is not affiliated with, endorsed by, or connected to Proton AG.
> Proton Drive is a trademark of Proton AG. This is an independent community project.
