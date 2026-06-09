# ProtonDrive Linux

[![CI](https://github.com/DonnieDice/protondrive-linux/actions/workflows/package-workflows.yml/badge.svg)](https://github.com/DonnieDice/protondrive-linux/actions/workflows/package-workflows.yml)
[![downloads](https://img.shields.io/github/downloads/DonnieDice/protondrive-linux/total?color=6d4aff)](https://github.com/DonnieDice/protondrive-linux/releases)
[![license](https://img.shields.io/badge/license-AGPL--3.0-6d4aff)](docs/LICENSE)
[![issues](https://img.shields.io/github/issues/DonnieDice/protondrive-linux?color=6d4aff)](https://github.com/DonnieDice/protondrive-linux/issues)

> This is the public **GitHub mirror**. Active development, CI/CD pipelines, and packaging happen on [**self-hosted GitLab**](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux). Every commit here is mirrored from there. See [CI Authority & GitHub Mirroring](docs/ci-cd/ci-authority-and-mirroring.md) for the full policy.

An unofficial desktop client for [Proton Drive](https://proton.me/drive) on Linux, built with [Tauri](https://tauri.app/) and [WebKitGTK](https://webkitgtk.org/).

---

## About

ProtonDrive Linux wraps Proton's web application in a native desktop window with system tray integration, native file sync, and comprehensive cross-distribution packaging. Authentication, encryption, and core file operations are handled by Proton's web app — this project provides the native shell and Linux integrations.

### Features

- Native desktop window with system tray integration
- Login, CAPTCHA, and two-factor authentication
- Proton Drive file browsing and downloads
- Experimental 2-way live sync (watch local folders, apply remote changes)
- Native packages for 17+ Linux targets
- Built with Rust + Tauri for small footprint and low resource usage

---

## Installation

Download from [GitHub Releases](https://github.com/DonnieDice/protondrive-linux/releases/latest).

| Format | Targets |
|--------|---------|
| **AppImage** | Universal Linux |
| **DEB** | Debian 12/13, Ubuntu 24.04/26.04 |
| **RPM** | Fedora 43/44, EL10, openSUSE Tumbleweed |
| **Flatpak** | GNOME 49/50 |
| **Snap** | core24, core26 |
| **APK** | Alpine 3.20/3.22/3.23 |
| **AUR** | `proton-drive` (Arch Linux) |

> Packages are not yet available on Flathub, Snap Store, or system repositories.

---

## Building from Source

```bash
# Clone the repository
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux

# Build WebClients (Proton's web app)
bash scripts/build-webclients.sh

# Install dependencies and build
npm ci
npx tauri build --bundles deb
```

### Prerequisites

- Rust (stable)
- Node.js 22+
- WebKitGTK 4.1, GTK3, libayatana-appindicator, OpenSSL, libsoup 3.0
- See [Contributing](docs/CONTRIBUTING.md) for distro-specific setup

---

## CI/CD Pipeline

The project runs a comprehensive CI/CD pipeline on self-hosted GitLab with 7 quality gates before builds:

| Stage | Jobs |
|-------|------|
| **Lint** | ShellCheck, shfmt, yamllint, actionlint, GitLab CI lint, Ruff (Python) |
| **Test** | Python script validation, version consistency, Rust coverage |
| **Security** | Gitleaks secrets, cargo-deny, npm audit, Trivy FS scan |
| **Build** | 17 platform targets (APK, AppImage, AUR, DEB, Flatpak, RPM, Snap) |
| **Smoke** | Install-and-run tests (deb, rpm, AppImage) |
| **Sign** | Cosign artifact signing, SLSA provenance attestation, SBOM generation |
| **Release** | Artifact upload, checksums, release creation |
| **Publish** | AUR, Flathub, Snap Store |

Builds are manual on MRs/branches and automated on `v*` tags. See [CI Pipeline Reference](docs/ci-cd/ci-pipeline-reference.md).

---

## Documentation

| | |
|---|---|
| [Architecture](docs/architecture/architecture.md) | System design, build system, proxy, navigation |
| [Build & Packaging](docs/build-packaging/build-packaging.md) | Support matrix, packaging policy, new target checklist |
| [CI/CD](docs/ci-cd/ci-pipeline.md) | Pipeline reference, authority, roadmap, release process |
| [Sync System](docs/sync/sync-system.md) | Live sync module, database, regression runbook |
| [Authentication](docs/auth/auth-module.md) | Auth flow, SSO authentication |
| [WebView](docs/webview/webview-integration.md) | WebView config, URL logging, storage |
| [API Reference](docs/api_v2_reference.md) | Tauri commands, events, REST endpoints |
| [Contributing](docs/CONTRIBUTING.md) | Dev setup, build rules, packaging guide |
| [Workflow](docs/reference/workflow.md) | Branching, PR, review, merge protocol |
| [Changelog](docs/CHANGELOG.md) | Release history |
| [Security](docs/SECURITY.md) | Vulnerability reporting |

---

## 2-Way Live Sync (Experimental)

The native sync layer watches a local folder and applies remote file changes. The web frontend must call Tauri commands to enable it.

| Command | Description |
|---------|-------------|
| `start_sync(path)` | Start watching a folder under `$HOME` |
| `stop_sync()` | Stop watching |
| `get_sync_status()` | Returns `{ enabled, folder_path, poll_interval_seconds }` |
| `handle_remote_update(change)` | Apply remote create/update/delete |
| `read_sync_file(rootPath, relativePath)` | Read local file for upload (max 100 MB) |

See [Live Sync Module](docs/sync/live-sync-module.md) for the full contract and constraints.

---

## Contributing

Contributions are welcome. All development follows the [workflow protocol](docs/reference/workflow.md):

1. **Issue** → Create a tracking issue
2. **Branch** → `feature/N`, `fix/N`, or `chore/N`
3. **PR** → Open against `main`, link to issue
4. **Review** → Address CI checks and review feedback
5. **Merge** → Squash-merge after approval

Commit messages follow `(#N) Description` format. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed build and packaging rules.

---

> **Disclaimer:** This project is not affiliated with, endorsed by, or connected to Proton AG. Proton Drive is a trademark of Proton AG. This is an independent community project.
