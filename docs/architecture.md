# Architecture — protondrive-linux

> **Version:** 1.4.4 · **License:** AGPL-3.0 · **Author:** DonnieDice

## Overview

protondrive-linux is a **Tauri v2 desktop client** for Proton Drive. It wraps the Proton WebClients (the official React/TypeScript web application) inside a native Linux window and adds Rust-backed features — HTTP proxying, live file sync, and local download handling — that a pure-web client cannot provide.

```
┌──────────────────────────────────────────────────────────────────┐
│                     Tauri v2 Shell (WebKitGTK)                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  WebClients Frontend (React / TypeScript)                   │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────────────────┐  │  │
│  │  │ Drive UI  │  │ Account   │  │ Web Worker (crypto)   │  │  │
│  │  │ (files,   │  │ (login,   │  │ or main-thread        │  │  │
│  │  │ sharing)  │  │ settings) │  │ fallback per distro)  │  │  │
│  │  └─────┬─────┘  └─────┬─────┘  └───────────┬───────────┘  │  │
│  │        └──────────────┼────────────────────┘              │  │
│  │                       │ fetch / XHR                        │  │
│  │                       ▼                                    │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │     Initialization Script (monkey-patches)            │  │  │
│  │  │  • fetch() → Tauri IPC proxy_request                 │  │  │
│  │  │  • XHR → Tauri IPC proxy_request                     │  │  │
│  │  │  • console.log → Rust js_log                         │  │  │
│  │  │  • blob URL downloads → Rust save_download            │  │  │
│  │  │  • CAPTCHA interception (error 9001)                 │  │  │
│  │  │  • Worker/SharedWorker override per distro type       │  │  │
│  │  └──────────────────────┬───────────────────────────────┘  │  │
│  └─────────────────────────┼──────────────────────────────────┘  │
│                            │ Tauri IPC (invoke)                  │
│  ┌─────────────────────────┼──────────────────────────────────┐  │
│  │             Rust Backend (src-tauri/src/)                   │  │
│  │  ┌──────────────────────┴──────────────────────────────┐   │  │
│  │  │  main.rs — App entry, window setup, IPC handlers    │   │  │
│  │  │  • proxy_request  — HTTP proxy via reqwest client   │   │  │
│  │  │  • save_download  — Blob download to ~/Downloads    │   │  │
│  │  │  • CAPTCHA flow   — Token/credential store          │   │  │
│  │  │  • Live sync CMDS — start/stop/status/remote-apply  │   │  │
│  │  │  • Navigation     — SSO URL rewrite, blob intercept │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  │                                                             │  │
│  │  ┌─────────────────────┐   ┌───────────────────────────┐   │  │
│  │  │  auth.rs            │   │  live_sync.rs              │   │  │
│  │  │  • SRP login flow   │   │  • Filesystem watcher      │   │  │
│  │  │  • TOTP / 2FA       │   │    (notify crate)          │   │  │
│  │  │  • Token refresh    │   │  • Remote change apply     │   │  │
│  │  │  • proton-srp crate │   │  • Path traversal protect  │   │  │
│  │  └─────────────────────┘   └───────────────────────────┘   │  │
│  │                                                             │  │
│  │  ┌─────────────────────────────────────────────────────┐   │  │
│  │  │  Shared State (AppState)                             │   │  │
│  │  │  • reqwest::Client (cookie jar)                      │   │  │
│  │  │  • LiveSyncManager                                   │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            │                                      │
│                            ▼                                      │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │  Proton API (mail.proton.me / verify.proton.me)            │   │
│  │  • Auth (SRP, 2FA, session refresh)                       │   │
│  │  • Drive data (files, folders, metadata, upload)          │   │
│  │  • CAPTCHA / Human Verification                           │   │
│  └────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. `main.rs` — Application Entry Point

**File:** `src-tauri/src/main.rs` (1196 lines)

The entry point performs these responsibilities:

| Responsibility | Details |
|---|---|
| **Environment setup** | Sets `WEBKIT_DISABLE_DMABUF_RENDERER`, `WEBKIT_DISABLE_COMPOSITING_MODE`, `GDK_GL=disable`, `GSK_RENDERER=cairo` to work around WebKitGTK GPU rendering issues on various Linux configurations. |
| **AppState** | Creates an `Arc<AppState>` containing a `reqwest::Client` with cookie jar enabled and a `LiveSyncManager`. |
| **Tauri builder** | Registers three plugins (`tauri_plugin_shell`, `tauri_plugin_dialog`, `tauri_plugin_notification`), manages the `AppState`, and registers 13 IPC commands. |
| **Window creation** | Opens a 1200×800 WebView window (min 800×600) loading `index.html` from the built WebClients frontend. DevTools are enabled. |
| **Initialization script** | Injects ~970 lines of JavaScript into every loaded page. See [Init Script](#init-script) below. |
| **Navigation handler** | Intercepts all page navigations to rewrite Proton SSO URLs and detect CAPTCHA state changes. |

**Registered Tauri Commands:**

| Command | Purpose |
|---|---|
| `proxy_request` | Proxies HTTP requests from the WebView through the Rust HTTP client. Handles cookie forwarding, URL rewriting (tauri://localhost → proton API), and header sanitization. |
| `js_log` | Forwards JavaScript console output to the Rust process log (`[JS] prefix). |
| `navigate_to_captcha` | Navigates the main window to a CAPTCHA verification URL (verify.proton.me) as a top-level document. |
| `get_captcha_return_url` | Returns the URL to navigate back to after CAPTCHA completes. |
| `store_verification_token` / `get_and_clear_verification_token` | Single-use token store — zero trust, cleared after first retrieval. |
| `store_login_credentials` / `get_and_clear_login_credentials` | Temporary credential storage to restore login forms after CAPTCHA navigation. |
| `save_download` | Saves blob/binary data to the user's `~/Downloads` directory. |
| `start_sync` / `stop_sync` / `get_sync_status` / `handle_remote_update` | Lifecycle and application of live sync operations (see [Live Sync](#3-live_syncrs-live-sync)). |

---

### 2. `auth.rs` — Proton SRP Authentication

**File:** `src-tauri/src/auth.rs` (418 lines)

Handles Proton's **SRP (Secure Remote Password)** authentication flow using the official `proton-srp` Rust crate.

**Auth Flow:**

```
User credentials  ──►  POST /api/core/v4/auth/info
                               │
                               ▼
                     Receive modulus, server ephemeral,
                     salt, SRP session ID
                               │
                     Compute client proof (proton-srp)
                               │
                               ▼
                     POST /api/core/v4/auth  (with proof)
                               │
                     ┌─────────┼─────────┐
                     ▼         ▼         ▼
                  Success   2FA (TOTP)  Human Verification
                     │         │         (error 9001)
                     │         ▼         │
                     │   POST /api/      │
                     │   core/v4/auth/   │
                     │   2fa             │
                     │         │         │
                     └────┬────┘         │
                          ▼              ▼
                    AuthSession      CAPTCHA flow
                    (uid, access,    (see navigation
                     refresh,        handler)
                     token_type)
```

**Key structures:**
- `AuthSession` — Holds UID, access token, refresh token, and token type.
- `AuthError` — Typed errors: `Network`, `Srp`, `InvalidResponse`, `TwoFactorRequired`, `InvalidCredentials`, `NotAuthenticated`, `HumanVerificationRequired`.
- `AuthManager` — Wraps the SRP authentication state with thread-safe `tokio::sync::RwLock`.

---

### 3. `live_sync.rs` — Live File Synchronization

**File:** `src-tauri/src/live_sync.rs` (425 lines)

Provides **bidirectional** sync between a local directory and Proton Drive. Not a full Dropbox-style sync — rather, it monitors a user-selected folder and can apply remote changes pushed from the server.

**Architecture:**

```
┌──────────────────┐     Tauri IPC      ┌──────────────────────┐
│  WebClients UI   │ ◄─────────────────► │  LiveSyncManager     │
│  (Drive frontend)│   "live-sync://     │  (Rust, in main.rs)  │
│                  │    local-change"    │                      │
│  start_sync()    │   events           │  ┌────────────────┐  │
│  stop_sync()     │                    │  │ notify watcher  │  │
│  get_sync_status │                    │  │ (inotify on     │  │
│  handle_remote_  │                    │  │  Linux)         │  │
│   update()       │                    │  │  recursive      │  │
└──────────────────┘                    │  │  background     │  │
                                        │  │  thread         │  │
                                        │  └────────────────┘  │
                                        │                      │
                                        │  Remote changes via  │
                                        │  apply_remote_change │
                                        │  (create/update/     │
                                        │   delete) with path  │
                                        │  traversal protection│
                                        └──────────────────────┘
```

**Key features:**

- **File watcher** — Uses `notify` crate (`RecommendedWatcher` = inotify on Linux). Monitors recursively with a background thread (`live-sync-watcher`).
- **Self-suppression** — Changes applied by `apply_remote_change` are tracked in a known-files cache (`HashMap<PathBuf, Instant>`) with a 30-second TTL to avoid echo loops.
- **Path traversal protection** — Validates that all sync paths reside under the user's home directory and rejects `..`, absolute paths, and prefix components.
- **Events** — Local changes are emitted as JSON events on the `"live-sync://local-change"` Tauri channel.
- **Remote changes** — Accepts base64-encoded file content via `RemoteSyncChange` struct, decodes and writes locally.

**Data structures:**

| Struct | Purpose |
|---|---|
| `LiveSyncEvent` | Emitted to frontend on local file changes (`kind`: create/modify/remove, `paths`: list of affected paths). |
| `LiveSyncStatus` | Returned from `get_sync_status`: `enabled` (bool) and `folder_path`. |
| `RemoteSyncChange` | Received from frontend to apply a remote file change (`relative_path`, `action`, `content_base64`). |
| `LiveSyncManager` | Stateful manager with mutex-guarded watcher, folder paths, and suppression cache. |

---

### 4. Init Script — WebView Monkey-patching

The initialization script injected via `WebviewWindowBuilder::initialization_script()` is the largest single piece of logic (~970 lines of JavaScript). It runs on every page load before any application code.

**What it patches:**

| Patch | Purpose |
|---|---|
| `fetch()` | Intercepts all `/api/` requests and routes them through the Rust `proxy_request` command for proper cookie handling and CORS avoidance. Non-API requests pass through to the native WebView fetch. |
| `XMLHttpRequest` | Same as `fetch()` — intercepts API calls for the XHR path. |
| `console.log/error/warn` | Forwards all JS console output to Rust via `js_log` for unified logging. |
| `URL.createObjectURL` | Tracks blob URLs so downloads can be saved to disk. |
| `window.open` | Intercepts blob URL opens for download handling. |
| Anchor `download` attribute | Captures filename from Proton's download logic and saves blobs via `save_download`. |
| `postMessage` handler | Captures CAPTCHA completion events (`HUMAN_VERIFICATION_SUCCESS`, `pm_captcha`) from Proton's verification pages. |
| `Worker` / `SharedWorker` | Disabled per distro type (see below). |
| Iframe `src` | Blocks CAPTCHA iframe creation — captcha only works as top-level document in WebKitGTK. |
| Unhandled errors/rejections | Forwards to Rust for diagnostics. |
| `document.createElement('a')` | Watches for dynamically created download anchors. |

**Distro-specific Worker handling:**

```javascript
// AppImage / AUR — native Workers supported, no override
// RPM / deb → Workers set to undefined (system WebKitGTK bug)
// Unknown → Worker/SharedWorker completely blocked with stubs
```

This is controlled at **compile time** via the `DISTRO_TYPE` environment variable.

---

### 5. Navigation & SSO Handling

The `on_navigation` callback rewrites Proton URL schemes to work inside the `tauri://localhost` context:

```
User clicks /login          → tauri://localhost/account/?product=drive
account.proton.me/*         → tauri://localhost/account/*
drive.proton.me/*           → tauri://localhost/*
account.localhost/u/X/*     → tauri://localhost/u/X/  (post-login redirect)
```

**CAPTCHA navigation detection** is stateful — the app tracks whether the WebView is currently on a CAPTCHA page via `ON_CAPTCHA_PAGE` atomic bool. When the user leaves a CAPTCHA page (verification complete), the app automatically navigates back to `tauri://localhost/account/` to retry the auth request with the verification token.

---

### 6. Build System

**package.json scripts:**

| Script | Command |
|---|---|
| `dev` | `tauri dev` — development mode with hot reload |
| `build:web` | `./scripts/build-webclients.sh` — clones, patches, and builds WebClients |
| `build` | `build:web && tauri build --bundles deb,rpm,appimage` |
| `build:deb` | Single-format builds (also `build:rpm`, `build:appimage`) |

**WebClients build pipeline** (`scripts/build-webclients.sh`):

1. Check cache — if WebClients dist exists and cache key matches, reuse it
2. Clone `https://github.com/ProtonMail/WebClients.git` (shallow, single-branch)
3. Run `scripts/fix_deps.py` to patch dependency versions
4. Apply patches from `patches/common/*.patch` to WebClients source
5. Install dependencies via Yarn (WebClients uses its own isolated Yarn workspace)
6. Build the `applications/drive` package

**Patches directory:** `patches/common/` contains Tauri-specific source patches applied at build time (e.g., `fix-tauri-worker-protocol.patch`).

---

### 7. Data Flow — End to End

```
User clicks "Open folder" in Drive UI
         │
         ▼
WebClients React component dispatches API call
         │
         ▼
Patched fetch() intercepts the /api/... request
         │
         ▼
window.__TAURI__.core.invoke('proxy_request', { method, url, headers, body })
         │
         ▼
Rust proxy_request handler:
  1. Rewrite URL (localhost → mail.proton.me)
  2. Build reqwest::Request with forwarded headers
  3. Send via cookie-authenticated client
  4. Collect response: status, body, set-cookie headers
  5. Return ProxyResponse to frontend
         │
         ▼
Init script reconstructs Response object:
  1. Create new Response(resp.body)
  2. Apply Set-Cookie headers to document.cookie
  3. If status 422 + Code 9001:
     a. Save login credentials
     b. Navigate to verify.proton.me (top-level)
     c. Wait for postMessage (HUMAN_VERIFICATION_SUCCESS)
     d. Store verification token
     e. Navigate back → retry auth with x-pm-human-verification-token header
  4. Return Response to calling code
         │
         ▼
React component receives response, updates UI
```

---

### 8. Key Technologies

| Technology | Version / Role |
|---|---|
| **Tauri** | v2 — Desktop application framework (Rust + WebView). Cargo crate `tauri = "2.0"` with `protocol-asset` feature. |
| **Rust** | Edition 2021 — Backend language. Binary name `proton-drive`. |
| **React** | Via Proton WebClients — Frontend UI framework (TypeScript). |
| **WebKitGTK** | System library — Renders the web frontend (`libwebkit2gtk-4.1-0` on Debian). |
| **SQLite** | Via WebClients `sync_db` — Local metadata/indexing for offline file listing. |
| **Proton API** | `https://mail.proton.me` — REST API for auth, drive operations, and file sync. |
| **notify** | v6.1 — Cross-platform filesystem watcher (inotify on Linux). |
| **reqwest** | v0.12 — Async HTTP client with cookie jar support. |
| **tokio** | v1 — Async runtime (`rt-multi-thread`). |
| **proton-srp** | SRP cryptographic authentication for Proton protocol. |
| **base64** | v0.22 — Encoding/decoding for sync content transfer. |
| **VitePress** | v1.6 — Documentation site builder. |

---

### 9. Bundle Targets & Distribution

| Format | Dependencies |
|---|---|
| **deb** (Debian/Ubuntu) | `libwebkit2gtk-4.1-0`, `libgtk-3-0`, `libayatana-appindicator3-1`, `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good` |
| **rpm** (Fedora/RHEL) | `webkit2gtk4.1`, `gtk3`, `libayatana-appindicator-gtk3` |
| **AppImage** (universal) | Bundles media framework if needed (`bundleMediaFramework: false`) |
| **AUR** (Arch Linux) | Community-maintained PKGBUILD |

All builds are produced with `npm run build` or targeted single-format commands. The same WebClients `dist/` is shared across all formats; distro-specific behavior (Worker support) is selected at compile time via the `DISTRO_TYPE` env var.

---

### Directory Layout (Key Paths)

```
protondrive-linux/
├── src-tauri/                         # Rust backend
│   ├── src/
│   │   ├── main.rs                    # Entry point + IPC handlers + init script
│   │   ├── auth.rs                    # SRP authentication
│   │   ├── live_sync.rs               # File watcher + remote change apply
│   │   └── index.html                 # HTML shell loading WebClients
│   ├── Cargo.toml                     # Rust dependencies & binary config
│   └── tauri.conf.json                # Tauri app config (window, bundle, plugins)
├── WebClients/                        # Cloned at build time (not committed)
│   └── applications/drive/dist/       # Built frontend output
├── scripts/
│   ├── build-webclients.sh            # Clone, patch, build WebClients
│   ├── fix_deps.py                    # Dependency fixer for WebClients
│   └── create_stubs.py                # Stub generation for missing modules
├── patches/
│   └── common/                        # Source patches applied to WebClients
├── package.json                       # Node scripts & devDependencies
└── docs/                              # Documentation site (VitePress)
```

---

### Security Model

| Layer | Measure |
|---|---|
| **Authentication** | SRP protocol (zero-knowledge password proof) via `proton-srp`. No plaintext passwords cross the wire. |
| **HTTP proxying** | Only `/api/` paths are proxied through Rust. Non-API requests go through native WebView fetch. |
| **Cookie handling** | reqwest cookie jar is the single source of truth. Set-Cookie headers forwarded to WebView for session decryption. |
| **Verification tokens** | Stored in Rust memory, cleared after single use ("zero trust"). Never persisted to disk. |
| **Login credentials** | Stored temporarily during CAPTCHA flow, cleared immediately after use. |
| **Sync origin guard** | Sync commands rejected unless origin is `tauri://localhost`. |
| **Sync path validation** | Only paths under the user's home directory are accepted. Path traversal (`..`, `/`) is rejected. |
| **Downloads** | Only written to `~/Downloads`. Filename is sanitized (query params stripped). |
| **CSP** | Explicitly set to `null` (disabled) — necessary for Proton WebClients to load resources from multiple origins. |
