# Configuration Reference

Reference for every constant, environment variable, timeout, and file path
in `protondrive-linux`. All values are current as of v2.0.0. Values marked
**compile-time** require a rebuild to change; **run-time** can be set in the
environment.

---

## Runtime Environment Variables

Variables set at process launch. Required for correct rendering and sandbox
behavior on Linux.

| Variable | Value | Purpose |
|---|---|---|
| `WEBKIT_DISABLE_DMABUF_RENDERER` | `1` | Disables DMA-BUF GPU buffer sharing — avoids rendering artifacts on many Linux GPU drivers |
| `WEBKIT_DISABLE_COMPOSITING_MODE` | `1` | Disables hardware compositing — prevents GPU driver crashes with WebKitGTK |
| `WEBKIT_FORCE_SANDBOX` | `0` | Disables WebKit's process sandbox — required for Tauri's IPC bridge to work |
| `GDK_GL` | `disable` | Disables GTK's OpenGL integration, forcing software rendering |
| `GSK_RENDERER` | `cairo` | Forces the Cairo 2D renderer — most compatible across Linux distributions |

These are set programmatically in `main()` at startup (line ~355 of `main.rs`)
and do not need to be set by the user. They are documented here for
transparency and troubleshooting.

---

## Build-Time Environment Variables

Set at compile time (via Cargo or shell). These become baked into the binary.

| Variable | Possible Values | Where Used | Purpose |
|---|---|---|---|
| `DISTRO_TYPE` | `aur`, `deb`, `rpm`, `appimage`, `apk`, `snap`, unset | `main.rs`, `build-system.md` | Controls Web Worker handling at runtime. See [Build System](build-system.md) §DISTRO_TYPE for the per-distro behavior matrix. |

Example:

```bash
DISTRO_TYPE=aur cargo build --release
```

When unset (default), no worker-specific init is injected. The WebKitGTK env
vars, sandbox flags, and renderer flags above are always set regardless of
`DISTRO_TYPE`.

### CI Smoke-Test Variable

| Variable | Purpose |
|---|---|
| `PROTONDRIVE_AUTO_SYNC_PATH` | Used in CI smoke tests to provide a pre-configured sync root directory path. Not used in production. |

---

## Compile-Time Constants

All values below are hard-coded in Rust source. Changing them requires a
rebuild.

### Sync Configuration (`main.rs`)

| Constant | Value | Notes |
|---|---|---|
| `DEFAULT_SYNC_ROOT_DIR` | `"ProtonDrive"` | The directory created under `$HOME` as the default sync root. Also shown in error messages. |
| `DEFAULT_REMOTE_SCOPE_COMPUTERS` | `"computers"` | The Proton Drive remote scope used for the "Computers" tab sync root registration. |
| `DEFAULT_DEVICE_TYPE_LINUX` | `"linux"` | Device type string registered with the Proton Drive API. |
| `MAX_SYNC_BRIDGE_FILE_BYTES` | `104,857,600` (100 MiB) | Maximum file size passed through the sync bridge from WebView to Rust. Files larger than this are rejected. |

### Sync Persistence (`main.rs`)

| Constant | Value | Notes |
|---|---|---|
| `SYNC_ROOT_CONFIG_FILE` | `"sync-root.txt"` | File in `<app_data_dir>` that persists the user's chosen sync root path. |

### Proxy Configuration (`main.rs`)

| Constant | Value | Notes |
|---|---|---|
| `PROXY_REQUEST_TIMEOUT` | `45 seconds` | Total time allowed for the entire proxy HTTP request-response cycle. |
| `PROXY_CONNECT_TIMEOUT` | `15 seconds` | Maximum time allowed to establish a TCP+TLS connection to the upstream Proton API. |

The proxy does **not** perform automatic retries — if a request fails with
502/504, the SPA's own retry logic (if any) handles it.

### Sync Polling (`live_sync.rs`)

| Constant | Value | Notes |
|---|---|---|
| `DEFAULT_SYNC_POLL_INTERVAL` | `30 seconds` | How often the poller thread checks the Proton API for remote changes. |

### Sync Database (`sync_db.rs`)

| Constant | Value | Notes |
|---|---|---|
| `SCHEMA_VERSION` | `3` | Current SQLite schema version. Used for migration gating. |

#### Remote Scopes

| Constant | Value | Notes |
|---|---|---|
| `REMOTE_SCOPE_COMPUTERS` | `"computers"` | Scope for files under the "Computers" tab. |
| `REMOTE_SCOPE_MY_FILES` | `"my_files"` | Scope for files under the "My Files" tab. |
| `REMOTE_SCOPE_UNMAPPED` | `"unmapped"` | Fallback scope for items not yet assigned to a known scope. |

#### Error Constants

| Constant | Value |
|---|---|
| `ERR_SYNC_DB_OPEN_FAILED` | `"Failed to open sync metadata database"` |
| `ERR_SYNC_DB_MIGRATE_FAILED` | `"Failed to migrate sync metadata database"` |
| `ERR_SYNC_DB_WRITE_FAILED` | `"Failed to write sync metadata"` |
| `ERR_SYNC_DB_READ_FAILED` | `"Failed to read sync metadata"` |

---

## Tauri Configuration (`tauri.conf.json`)

| Key | Value |
|---|---|
| Bundle identifier | `com.proton.drive` |
| Product name | `Proton Drive` |
| Version | `2.0.0` |
| Bundle targets | `deb`, `rpm`, `appimage` |
| App URL (frontendDist) | `../dist` |
| Dev URL | `http://localhost:1420` |

---

## Cargo Feature Flags

| Feature | Default | Purpose |
|---|---|---|
| `custom-protocol` | ✅ | Enables `tauri/custom-protocol`. Required for the `tauri://` protocol that serves the SPA and handles IPC. |

No optional features exist. The only feature gate is the default `custom-protocol`.

---

## File System Paths

All paths below are from the perspective of a Linux installation. Paths use
`~` as shorthand for the user's home directory.

### Application Data (`$XDG_DATA_HOME` or `~/.local/share`)

| Path | Purpose |
|---|---|
| `<app_data>/com.proton.drive/` | Tauri app data directory root |
| `<app_data>/com.proton.drive/sync-metadata.db` | SQLite sync metadata database (WAL mode) |
| `<app_data>/com.proton.drive/sync-root.txt` | Persists user-selected sync root path |
| `<app_data>/com.proton.drive/webview-data/` | WebKit persistent storage (IndexedDB, localStorage, etc.) |

### User Data

| Path | Purpose |
|---|---|
| `~/ProtonDrive/` | **Default sync root** — created at first launch if no prior sync root is persisted |
| `~/Downloads/` | **File download destination** — blob downloads from the Drive web app are saved here |
| `<user-selected path>/` | **Custom sync root** — set via the `set_sync_root` Tauri command, persisted in `sync-root.txt` |

### Sync Root Layout

Inside the sync root, the app creates:

```
~/ProtonDrive/
├── my_files/          # Remote "My Files" scope — two-way sync
├── computers/         # Remote "Computers" scope — two-way sync
└── .sync/             # Per-item state caches, suppression hashes
```

---

## API Endpoints (Hard-Coded)

The proxy intercepts and rewrites URLs at runtime. The following Proton domains
are hard-coded for routing decisions:

| Hostname | Purpose | Route |
|---|---|---|
| `account.proton.me` | SSO authentication | Rewritten to local `tauri://localhost/account/` path |
| `drive.proton.me` | Drive SPA | Served via `tauri://localhost/` custom protocol |
| `mail.proton.me` | Mail SPA (unused) | Served via `tauri://localhost/` |
| `calendar.proton.me` | Calendar SPA (unused) | Served via `tauri://localhost/` |
| `proton.me` | General Proton site | Served via `tauri://localhost/` |
| `api.proton.me` | Proton API | Proxied through Rust `reqwest` client |
| `drive-api.proton.me` | Drive-specific API | Proxied through Rust `reqwest` client |

See [Proxy System](proxy-system.md) and [Proton Navigation](proton-navigation.md)
for the full routing decision tree.

---

## Internal Limits

| Limit | Value | Notes |
|---|---|---|
| Max file size through sync bridge | 100 MiB | `MAX_SYNC_BRIDGE_FILE_BYTES` — larger files are rejected |
| Max blob download size | WebView memory | No hard cap; limited by available JS heap. >500 MiB may cause memory pressure. |
| Concurrent downloads | Unlimited (practical: JS heap) | Each download holds the full file in memory. See [Blob Downloads](blob-downloads.md). |
| Proxy request ID counter | `u64` | Monotonically increasing, used for log correlation only. Wraps at 2⁶⁴. |
| Concurrent proxy requests | Unlimited (practical: Rust async) | Reqwest client uses connection pooling. |
| Concurrent sync operations | Single-threaded | One watcher thread + one poller thread. See [Live Sync Module](live-sync-module.md). |

---

## Logging

The app uses `println!` / `eprintln!` for all log output — there is no
structured logging framework (no `env_logger`, `tracing`, or `log` crate).

| Log prefix | Source |
|---|---|
| `[Sync]` | Sync manager, root path validation, start/stop events |
| `[Download]` | Blob download pipeline |
| `[Storage]` | WebView data directory initialization |
| `[Proxy]` | Proxy request/response lifecycle (suppressed in release builds for performance) |
| `[Navigate]` | URL rewriting decisions |
| `[App]` | Startup sequence |

To view logs, run the app from a terminal. There is no log file written to disk.

---

## See Also

- **[Architecture](ARCHITECTURE.md)** — How all modules and constants fit together
- **[Sync System](sync-system.md)** — Full sync pipeline, Tauri command wiring
- **[Proxy System](proxy-system.md)** — Proxy architecture and request lifecycle
- **[Build System](build-system.md)** — DISTRO_TYPE, feature flags, platform matrix
- **[CI Pipeline Reference](ci-pipeline-reference.md)** — CI jobs, env vars, artifact naming
- **[Live Sync Module](live-sync-module.md)** — Watcher/poller threads, event contract
