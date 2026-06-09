# ProtonDrive Linux

[![latest](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux/-/badges/master.svg?label=latest&color=6d4aff)](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux/-/releases)
[![downloads](https://img.shields.io/github/downloads/DonnieDice/protondrive-linux/total?color=6d4aff)](https://github.com/DonnieDice/protondrive-linux/releases)
[![license](https://img.shields.io/badge/license-AGPL--3.0-6d4aff)](docs/LICENSE)
[![issues](https://img.shields.io/github/issues/DonnieDice/protondrive-linux?color=6d4aff)](https://github.com/DonnieDice/protondrive-linux/issues)

> **📍 Repository status:** This is the **public mirror** of the project. Active development, full CI/CD pipelines, packaging, and merges happen on [**self-hosted GitLab**](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux) — every commit here is mirrored from there. Issues and Pull Requests opened on GitHub are automatically synced to GitLab for triage and review via the [sync-to-gitlab workflow](.github/workflows/sync-to-gitlab.yml). GitHub Actions here only run lightweight final-verification checks (see [Sanity Checks](.github/workflows/sanity.yml)); package builds and releases are produced on GitLab. See [CI Authority & GitHub Mirroring](docs/ci-authority-and-mirroring.md) for the full policy.

An unofficial desktop client for [Proton Drive](https://proton.me/drive) on Linux.

---

## About

ProtonDrive Linux wraps the official [Proton Drive](https://proton.me/drive) web interface in a native Linux desktop window using [Tauri](https://tauri.app/) and [WebKitGTK](https://webkitgtk.org/). Authentication, encryption, and file operations are handled by Proton's web app - this project provides the native shell, system tray integration, and cross-distro packaging.

**Features:**

- Desktop window for Proton Drive with system tray integration
- Login, CAPTCHA, and two-factor authentication support
- Proton Drive file browsing and downloads (saved to `~/Downloads`)
- Experimental 2-way live sync (watch a local folder and apply remote changes)
- Native packages for most major Linux distributions
- Built with Rust + Tauri for a small footprint and low resource usage

> **Packages are not yet available on Flathub, Snap Store, or system repositories.** For now, download from [Releases](https://github.com/DonnieDice/protondrive-linux/releases/latest).

## 2-Way Live Sync (Experimental)

The native sync layer lets the Proton Drive web app watch a local folder and apply remote file changes into it. This is **experimental** - the web frontend must call the Tauri commands to use it.

Operational notes, weak areas, and the `~/Pictures` test plan are documented in [Two-Way Sync Notes](docs/sync.md).

### How it works

1. **Choose a sync folder** - the web app calls `start_sync(path)` with any directory under `$HOME`. The path must exist and be a directory. Paths outside `$HOME` are rejected for safety.
2. **Local changes are detected** - a recursive file watcher monitors the folder for creates, modifies, and deletes. Events are emitted as `live-sync://local-change` to the frontend.
3. **Remote changes are applied** - the frontend calls `handle_remote_update(change)` to write or delete files in the sync folder. Relative paths are validated against the sync root - symlink traversal and path traversal (`../`) are blocked.

### Tauri commands

| Command | Description |
|---------|-------------|
| `start_sync(path)` | Start watching a folder. `path` must be an existing directory under `$HOME`. |
| `stop_sync()` | Stop watching and release the file watcher. |
| `get_sync_status()` | Returns `{ enabled, folder_path, poll_interval_seconds }`. |
| `set_sync_root(path)` | Persist a new sync directory and start sync. |
| `handle_remote_update(change)` | Apply a remote change. `change` is `{ relativePath, action, contentBase64 }` where `action` is `"create"`, `"update"`, or `"delete"`. |
| `read_sync_file(rootPath, relativePath)` | Zero-trust local file read for upload (max 100 MB). Rejects symlinks and path traversal. |
| `get_sync_device_name()` | Return the sanitized Linux device name used with the Proton Drive SDK. |

### Constraints

- The sync folder **must** be under `$HOME` (validated on start).
- Symlinks anywhere in the target path are rejected.
- Path components like `..` or root-dir references in `relativePath` are rejected.
- A suppression cache (4096 entries, 30 s TTL) prevents watcher ping-pong when remote writes land.
- Commands are only accepted from `tauri://localhost` or `tauri://tauri.localhost`.

## Documentation

| | |
|---|---|
| [Workflow](docs/workflow.md) | Branch, PR, review, and merge guide |
| [CI Authority & GitHub Mirroring](docs/ci-authority-and-mirroring.md) | GitLab CI authority, GitHub mirror policy, and release ownership |
| [Two-Way Sync Notes](docs/sync.md) | Sync bridge contract, weak areas, and test plan |
| [Login & Sync Regression Runbook](docs/login-sync-regression-runbook.md) | Manual login, 2FA, and sync acceptance procedures |
| [v2 API Reference](docs/api_v2_reference.md) | REST endpoints, Tauri commands, events, and curl examples |
| [Contributing](docs/CONTRIBUTING.md) | Detailed dev, build, and packaging rules |
| [Packaging & Compatibility](docs/packaging.md) | Support matrix, compatibility gates, patch policy |
| [Changelog](docs/CHANGELOG.md) | Release history |
| [Contributors](docs/contributors.md) | Community contributions |
| [License](docs/LICENSE) | AGPL-3.0 or later |
| [Security Policy](docs/SECURITY.md) | Vulnerability reporting |
| [Code of Conduct](docs/CODE_OF_CONDUCT.md) | Community standards |

&nbsp;

> **Disclaimer:** This project is not affiliated with, endorsed by, or connected to Proton AG.
> Proton Drive is a trademark of Proton AG. This is an independent community project.
