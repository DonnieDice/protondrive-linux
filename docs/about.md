---
title: "About ProtonDrive Linux"
created: 2026-05-28
updated: 2026-05-28
type: architecture
tags: [architecture, sync, auth]
sources:
  - []
editLink: true
---

# About ProtonDrive Linux

ProtonDrive Linux wraps the official [Proton Drive](https://proton.me/drive) web
interface in a native Linux desktop window using [Tauri](https://tauri.app/) and
[WebKitGTK](https://webkitgtk.org/). Authentication, encryption, and file
operations are handled by Proton's web app — this project provides the native
shell, system tray integration, and cross-distro packaging.

## Features

- **Desktop window** for Proton Drive with system tray integration
- **Login, CAPTCHA, and two-factor authentication** support
- **Proton Drive file browsing and downloads** saved to `~/Downloads`
- **Experimental 2-way live sync** — watch a local folder and apply remote
  changes
- **Native packages** for most major Linux distributions
- **Rust + Tauri** for a small footprint and low resource usage

> Packages are not yet available on Flathub, Snap Store, or system repositories.
> For now, download from [Releases](https://github.com/DonnieDice/protondrive-linux/releases/latest).

## 2-Way Live Sync (Experimental)

The native sync layer lets the Proton Drive web app watch a local folder and
apply remote file changes into it. This is **experimental** — the web frontend
must call the Tauri commands to use it.

### How It Works

1. **Choose a sync folder** — the web app calls `start_sync(path)` with any
   directory under `$HOME`. The path must exist and be a directory. Paths
   outside `$HOME` are rejected for safety.
2. **Local changes are detected** — a recursive file watcher monitors the folder
   for creates, modifies, and deletes. Events are emitted as
   `live-sync://local-change` to the frontend.
3. **Remote changes are applied** — the frontend calls
   `handle_remote_update(change)` to write or delete files in the sync folder.
   Relative paths are validated against the sync root — symlink traversal and
   path traversal (`../`) are blocked.

### Tauri Commands

| Command | Description |
|---------|-------------|
| `start_sync(path)` | Start watching a folder. `path` must be an existing directory under `$HOME`. |
| `stop_sync()` | Stop watching and release the file watcher. |
| `get_sync_status()` | Returns `{ enabled, folder_path }`. |
| `handle_remote_update(change)` | Apply a remote change. `change` is `{ relativePath, action, contentBase64 }` where `action` is `"create"`, `"update"`, or `"delete"`. |

### Constraints

- The sync folder **must** be under `$HOME` (validated on start).
- Symlinks anywhere in the target path are rejected.
- Path components like `..` or root-dir references in `relativePath` are
  rejected.
- A suppression cache (4096 entries, 30 s TTL) prevents watcher ping-pong when
  remote writes land.
- Commands are only accepted from `tauri://localhost` or
  `tauri://tauri.localhost`.

## Disclaimer

> This project is not affiliated with, endorsed by, or connected to Proton AG.
> Proton Drive is a trademark of Proton AG. This is an independent community
> project.
