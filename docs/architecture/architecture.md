# Proton Drive for Linux — Architecture

> **Version:** 1.4.4  
> **Last updated:** 2026-05-30  
> **License:** AGPL-3.0

---

## 1. System Overview

Proton Drive for Linux is a **Tauri v2 desktop application** that wraps Proton's existing Drive WebClients in a native window and augments them with a Rust backend. The Rust layer provides:

- SRP-based authentication (bypassing the WebView's browser-based auth)
- An HTTP proxy that routes API calls from the WebView through a shared `reqwest::Client` with cookie jar
- A filesystem watcher (`notify`) that feeds local file changes back into the WebClients via Tauri events
- Remote change application (pull-based sync)
- CAPTCHA/hCaptcha handling via top-level navigation
- Blob download interception and save-to-downloads

The frontend is **Proton's own web application** built from the `WebClients` monorepo, served from `WebClients/applications/drive/dist/` via the Tauri asset protocol.

---

## 2. Component Map

```
src-tauri/src/
├── main.rs             # Entry point, AppState, all Tauri commands, WebView init script
├── auth.rs             # AuthManager — SRP authentication, token refresh, 2FA
├── live_sync.rs        # LiveSyncManager — filesystem watcher, remote change application
├── proton_navigation.rs # URL rewriting: SSO redirects, CAPTCHA detection, unsupported app redirects
├── sync_db.rs          # SQLite schema, migrations, item tracking
├── webview_cookies.rs  # WebKit cookie jar integration: read, merge, store
├── webview_storage.rs  # Persistent WebView data directory provisioning
└── url_log.rs          # URL sanitization for log output
```

### 2.1 `AppState` (main.rs:51-55)

```rust
struct AppState {
    client: Client,
    cookie_jar: Arc<Jar>,
    sync_manager: live_sync::LiveSyncManager,
}
```

Managed as `Arc<AppState>` and injected into every Tauri command via `tauri::State<'_, Arc<AppState>>`. The `Client` is a `reqwest::Client` with `cookie_store(true)` — it acts as the shared HTTP client with automatic cookie persistence.

### 2.2 Static globals (main.rs)

Several `std::sync::Mutex` statics exist for zero-trust transient state during the CAPTCHA flow:

| Static | Type | Purpose |
|--------|------|---------|
| `CAPTCHA_RETURN_URL` | `Mutex<Option<String>>` | URL to navigate back to after captcha completes |
| `ON_CAPTCHA_PAGE` | `AtomicBool` | Tracks whether the WebView is currently on a captcha page |
| `PENDING_VERIFICATION` | `Mutex<Option<(String, String)>>` | Verification token + type, cleared after single use |
| `PENDING_CREDENTIALS` | `Mutex<Option<(String, String)>>` | Login credentials (username, password) saved during captcha flow, cleared after single use |

All four are deliberately **in-memory-only** with zero-trust semantics — cleared immediately after retrieval.

### 2.3 Module: `main.rs`

Owns:
- `fn main()` — sets `WEBKIT_DISABLE_DMABUF_RENDERER`, `WEBKIT_DISABLE_COMPOSITING_MODE`, `WEBKIT_FORCE_SANDBOX`, `GDK_GL`, `GSK_RENDERER` env vars for WebKitGTK compatibility; builds `AppState`; registers Tauri plugins (shell, dialog, notification); runs the builder
- **16 Tauri commands** (registered via `generate_handler!` at line 1851)
- **The WebView initialization script** (~688 lines of injected JS that patches `fetch`, `XMLHttpRequest`, `console`, `URL.createObjectURL`, `window.open`, `document.createElement`, anchors, iframe behavior, and Worker compatibility)
- The **`on_navigation` callback** that rewrites Proton URLs to local `tauri://localhost/...` paths

### 2.4 Module: `auth.rs`

Owns `AuthManager`:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `get_auth_info(username)` | `POST /api/auth/v4/info` | Fetches SRP parameters (modulus, salt, server ephemeral, version) |
| `submit_auth(...)` | `POST /api/auth/v4` | Sends client ephemeral + proof, receives session tokens |
| `login(username, password)` | — | Orchestrates the full SRP flow (above two steps + server proof verification) |
| `submit_2fa(totp_code)` | `POST /api/auth/v4/2fa` | Completes a 2FA challenge |
| `refresh_token()` | `POST /api/auth/v4/refresh` | Refreshes `access_token` using `refresh_token` |
| `logout()` | `DELETE /api/auth/v4` | Invalidates session server-side |

`AuthSession` (struct):
```rust
pub struct AuthSession {
    pub uid: String,
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,   // e.g. "Bearer"
}
```

The `AuthManager` uses its own `reqwest::Client` (separate from AppState's) with `redirect::Policy::none()`.

### 2.5 Module: `live_sync.rs`

Owns `LiveSyncManager`:

| Field | Type | Purpose |
|-------|------|---------|
| `watcher` | `Mutex<Option<RecommendedWatcher>>` | `notify` filesystem watcher instance |
| `folder` | `Mutex<Option<PathBuf>>` | User-chosen sync root directory |
| `root_canonical` | `Mutex<Option<PathBuf>>` | Canonicalized sync root (for path-escape checks) |
| `worker` | `Mutex<Option<JoinHandle<()>>>` | OS thread running the watcher event loop |
| `known_files` | `Arc<Mutex<HashMap<PathBuf, Instant>>>` | Suppression cache to prevent echo loops (TTL: 30s, max: 4096 entries) |

| Public method | Purpose |
|--------------|---------|
| `start(app_handle, folder)` | Starts `notify::RecommendedWatcher` on the folder, spawns worker thread |
| `stop()` | Drops watcher, joins worker thread, clears `known_files` |
| `status()` | Returns `LiveSyncStatus { enabled, folder_path }` |
| `apply_remote_change(change)` | Applies a `RemoteSyncChange` (create/update/delete) to local filesystem |

`LiveSyncEvent` (emitted via Tauri event bus): `{ kind: "create"|"modify"|"remove", paths: Vec<String> }` — emitted on the `"live-sync://local-change"` channel.

`RemoteSyncChange` (input from WebClients): `{ relativePath, action, contentBase64? }`.

---

## 3. Auth Flow

```
User enters credentials in WebView
        │
        ▼
  fetch(/api/core/v4/auth/info)  ──intercepted──►  proxy_request()
        │                                               │
        │                                        POST https://mail.proton.me/api/auth/v4/info
        │                                               │
        ◄────────── SRP parameters (modulus, salt, server ephemeral, version) ──────────┘
        │
        ▼
  Rust native code: SRPAuth::with_pgp() → generate_proofs()
        │
        ▼
  fetch(/api/core/v4/auth)  ──intercepted──►  proxy_request()
        │                                               │
        │                                        POST https://mail.proton.me/api/auth/v4
        │                                        (ClientEphemeral, ClientProof, SRPSession)
        │                                               │
        ◄────────── AuthSession (UID, access_token, refresh_token, token_type) ──────────┘
        │
        ▼
  Server proof verified via SRPAuth::compare_server_proof()
        │
        ├── [2FA enabled] → submit_2fa(totp) → POST /api/auth/v4/2fa → final session
        └── [No 2FA]      → session stored in AuthManager
```

**Token propagation:**
- The `AuthManager` stores the `AuthSession` in memory
- When the WebView's intercepted `fetch()` makes API calls, the shared `reqwest::Client` (with cookie jar) handles cookie-based authentication automatically via the `proxy_request` command
- Response cookies are written directly to the WebView's native WebKit cookie manager via `store_webview_cookie()`, keeping the WebView's session in sync with the proxy HTTP client

---

## 4. HTTP Proxy Layer

### 4.1 How it works

1. The WebView's initialization script patches `window.fetch` and `window.XMLHttpRequest`
2. For any URL containing `/api/`, the request is redirected to the `proxy_request` Tauri command instead of making a real HTTP request
3. The Rust `proxy_request` handler (main.rs:391-514):
   - Rewrites URLs: `localhost/api/...` → `https://mail.proton.me/api/...`, resolves `tauri://` scheme URLs, handles relative paths
   - Creates a `reqwest::Request` with the forwarded headers (except `Host` and `Cookie` — cookies are merged from both WebKit's native jar and the reqwest jar via `combined_cookie_header()`)
   - Sends the request through the shared `AppState.client` (which has an automatic cookie jar)
   - Routes `Set-Cookie` response headers directly into the WebView's native WebKit cookie manager via `store_webview_cookie()`, bypassing JavaScript-land entirely
   - Returns `ProxyResponse { status, headers, body }` to the JS side

4. The JS side reconstructs a `Response` object. Cookies are already in WebKit's native cookie store — no `document.cookie` manipulation needed.

### 4.2 Why this exists

WebKitGTK's cookie handling is inconsistent across Linux distributions. By routing all API calls through a `reqwest::Client` with a programmatic cookie jar (instead of relying on WebKit's HTTP stack), the app gets deterministic cookie behavior regardless of the system's WebKitGTK build.

### 4.3 URL rewriting rules

| Input pattern | Rewritten to |
|---------------|--------------|
| `https://localhost/api/...` | `https://mail.proton.me/api/...` |
| `http://localhost/api/...` | `https://mail.proton.me/api/...` |
| `tauri://localhost/api/...` | Extract `/api/...` path → `https://mail.proton.me/api/...` |
| `tauri://*/api/...` | Same extraction |
| `/api/...` | `https://mail.proton.me/api/...` |
| `https://...` (any other) | Used as-is |
| `//...` (protocol-relative) | JS fixes to `/...` before proxying |

### 4.4 Key constants

`PROTON_API_BASE` (`"https://mail.proton.me"` — main.rs:35) — The base URL for all proxied API requests.

---

## 5. Sync Flow

### 5.1 Local → Remote

```
User sets sync root via Tauri UI
        │
        ▼
  start_sync(path) Tauri command
        │
        ├── validate_sync_root_path(path): canonicalize, must be under $HOME
        │
        ├── ensure_sync_command_allowed(window): origin must be tauri://localhost or tauri://tauri.localhost
        │
        └── LiveSyncManager::start(app, path)
              │
              ├── Creates notify::RecommendedWatcher (recursive, debounce disabled)
              ├── Spawns OS thread "live-sync-watcher"
              │     └── Event loop: reads fs events → filters against known_files suppression cache
              │           → emits "live-sync://local-change" event with LiveSyncEvent
              │             {
              │               kind: "create" | "modify" | "remove",
              │               paths: ["/home/user/sync/doc.pdf", ...]
              │             }
              │
              └── WebClients receive event → upload content to Proton Drive via SDK device API
```

The **suppression cache** (`known_files`) prevents echo loops: when the Rust backend writes a file (from a remote change), it marks the path as known. The watcher thread skips events on known paths for `SUPPRESSION_TTL` (30 seconds). Cache is capped at `SUPPRESSION_CACHE_MAX` (4096 entries).

### 5.2 Remote → Local

```
WebClients detect remote change (via polling or push)
        │
        ▼
  handle_remote_update(RemoteSyncChange) Tauri command
        │
        ├── ensure_sync_command_allowed: origin check
        │
        └── LiveSyncManager::apply_remote_change(change)
              │
              ├── validate_path_within_root(canonical_root, target):
              │     Checks each component for symlinks (rejected if found)
              │     Canonicalizes the target path
              │     Verifies it starts with canonical_root
              │
              ├── [create | update]:
              │     Decodes base64 content
              │     Creates parent directories
              │     Marks file in known_files (suppression for watcher)
              │     Writes file
              │
              └── [delete]:
                    Marks file in known_files
                    Removes file if exists
```

### 5.3 Sync command security

The `ensure_sync_command_allowed` function (main.rs:517-538) verifies the WebView's current URL origin is `tauri://localhost` or `tauri://tauri.localhost` before allowing any sync operation. This prevents sync commands from being invoked from arbitrary web pages loaded in the WebView.

The `validate_sync_root_path` function (main.rs:540-556) ensures the sync root is a subdirectory of the user's home directory.

---

## 6. Navigation Routing (SSO / Login / Captcha)

The `on_navigation` callback (main.rs:1602-1808) intercepts all WebView navigations and rewrites them:

| Incoming URL | Action |
|--------------|--------|
| `blob:...` | Blocks navigation, extracts blob from `__blobUrls`, invokes `save_download` |
| `/login?...` | Rewrites to `tauri://localhost/account/?product=drive`, filters `reason=`/`type=` params |
| `account.proton.me/...` | Rewrites to `tauri://localhost/account/...` |
| `drive.proton.me/...` | Rewrites to `tauri://localhost/...` |
| `account.localhost/u/X/drive/...` / `localhost/account/u/X/drive/...` | Post-login redirect to `tauri://localhost/` (root, 250ms delay via about:blank) — deep `/u/X/` paths break WebKitGTK asset protocol/IPC |
| `hcaptcha.com` / `*.hcaptcha.com` | Allowed through (captcha widget resources) |
| `mail.proton.me/api/core/v4/captcha` / `mail.proton.me/captcha/...` / `verify.proton.me` / `verify-api.proton.me` | Allowed (captcha flow), sets `ON_CAPTCHA_PAGE` |
| Any `/api/...` path | **Blocked** — API calls should use `fetch`, not navigation |
| All others | Allowed only if scheme is `tauri` or `about`, or host is `localhost`/`tauri.localhost` |

The SSO flow works as follows:
1. User navigates to `/login` (or `account.proton.me`)
2. Navigation is rewritten to `tauri://localhost/account/?product=drive`
3. Account WebClient handles login (SRP via the proxy, since `fetch` is intercepted)
4. After login, the account app redirects to `account.localhost/u/0/drive/account`
5. The `on_navigation` callback intercepts this and navigates to `about:blank` (killing the account document), then after 250ms redirects to `tauri://localhost/` — the Drive app root
6. The Drive init script's SSO guard detects a persisted `ps-<localID>` session in localStorage and uses `history.replaceState` to restore the `/u/<localID>/` route without a full WebView reload, avoiding the WebKitGTK asset protocol/IPC freeze bug

---

## 7. CAPTCHA / Human Verification Flow

When the Proton API returns error code `9001` (HumanVerificationRequired), the system:

1. The proxied `fetch` response is returned to JS with status 422
2. JS code in the initialization script parses the body for `Code === 9001`
3. If `captchaPending` is false, it saves current login credentials (email/password) via `store_login_credentials`
4. Calls `navigate_to_captcha(captcha_url, return_url)` — navigates the **entire window** to `verify.proton.me` (top-level navigation, not an iframe — captcha only works as top-level in WebKitGTK)
5. User completes captcha/hCaptcha on the external page
6. The page sends a `postMessage` with type `HUMAN_VERIFICATION_SUCCESS` (or `pm_captcha`) containing the verification token
7. JS navigates the window to `tauri://localhost/account/?hv_token=...&hv_type=...` — the token is carried through URL query params because external verify pages cannot reliably use Tauri IPC
8. The `on_navigation` callback's captcha completion handler (via `captcha_completion_token()`) extracts the token and type from the URL query params, stores them in `PENDING_VERIFICATION`, then navigates to `tauri://localhost/account/`
9. On the account page, the initialization script restores saved credentials via `get_and_clear_login_credentials()` and auto-fills/submits the login form
10. The auth request goes through the proxy again, which now includes `x-pm-human-verification-token` and `x-pm-human-verification-token-type` headers (retrieved via `get_and_clear_verification_token()`)

---

## 8. WebKitGTK Worker Compatibility

The `DISTRO_TYPE` environment variable (set at build time) determines how Web Workers are handled:

| DISTRO_TYPE | Worker handling | Rationale |
|-------------|----------------|-----------|
| `appimage` | **Native** — Workers left as-is | Bundled WebKitGTK supports Workers correctly |
| `aur` | **Native** — same as appimage | Bundled/up-to-date WebKitGTK |
| `rpm`, `deb` | **Disabled** — `window.Worker = undefined` | System WebKitGTK throws "operation is insecure" for Workers; Proton falls back to main-thread crypto |
| `flatpak`, `snap` | **Disabled** — same as rpm/deb | Sandboxed WebKitGTK may have Worker restrictions |
| `None` (unset) | **Disabled** — same as rpm/deb | Safe default for unknown distros |
| Unknown value | **Full override** — custom Worker stubs + error suppression | Maximum compatibility fallback |

When Workers are disabled, Proton WebClients automatically detect the absence of `Worker`/`SharedWorker` and fall back to main-thread cryptographic operations (ref: `packages/shared/lib/helpers/setupCryptoWorker.ts` line 19).

---

## 9. Download Interception

Since WebKitGTK does not reliably handle `Content-Disposition: attachment` headers when proxied through `fetch`, downloads are intercepted at multiple levels:

1. **`URL.createObjectURL`** is monkey-patched to track blob URLs in a `Map`
2. **`window.open`** — blob URL opens are intercepted, forwarded to `handleBlobDownload()`
3. **Anchor clicks** — `<a href="blob:...">` clicks are intercepted (capturing phase)
4. **`setAttribute('download', ...)`** and **`HTMLAnchorElement.download` property setter** are patched to capture download filenames
5. **`document.createElement`** for `<a>` tags gets a `MutationObserver` watching the `download` attribute
6. **`on_download`** callback in Rust sets download destinations to `~/Downloads/<filename>`
7. **`on_navigation`** intercepts `blob:` scheme navigations and triggers `handleBlobDownload` via `eval`

The `save_download` Tauri command (main.rs:176-199) writes bytes to the user's Downloads directory.

---

## 10. WebView Storage

Persistent WebView session data (localStorage, IndexedDB, cookies) is stored at the default Tauri v2 path:

```
~/.local/share/com.proton.drive/
```

This is where Proton WebClients store their encrypted session state (`ps-*` keys in localStorage), cached API responses, and IndexedDB databases.

---

## 11. Key Constants and Their Purpose

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| `PROTON_API_BASE` | `"https://mail.proton.me"` | main.rs:35 | Base URL for all proxied API requests |
| `ERR_SYNC_NOT_ALLOWED` | `"Sync operation is not allowed in this context"` | main.rs:38 | Error message when sync commands come from disallowed origins |
| `SUPPRESSION_TTL` | `30 seconds` | live_sync.rs:20 | Duration during which a file write is suppressed from watcher events (prevents echo loops) |
| `SUPPRESSION_CACHE_MAX` | `4096` | live_sync.rs:21 | Maximum entries in the known-files suppression cache |
| `ERR_SYNC_SETUP_FAILED` | `"Failed to start live sync"` | live_sync.rs:13 | Generic watcher initialization error |
| `ERR_SYNC_NOT_ACTIVE` | `"Live sync is not active"` | live_sync.rs:15 | Error when applying remote changes without an active sync |
| `ERR_SYNC_INVALID_TARGET` | `"Invalid sync target path"` | live_sync.rs:19 | Path traversal / symlink escape error |

---

## 12. Dependency Map

```
┌─────────────────────────────────────────────────────┐
│                    Tauri v2                          │
│  ┌──────────────────────────────────────────────┐   │
│  │            WebView (WebKitGTK)                │   │
│  │  ┌────────────────────────────────────────┐  │   │
│  │  │  Proton Drive WebClient                 │  │   │
│  │  │  (WebClients/applications/drive/dist)   │  │   │
│  │  │  Patched: fetch, XHR, console, blob,    │  │   │
│  │  │  iframe, anchor, Worker                 │  │   │
│  │  │  Events: live-sync://local-change       │  │   │
│  │  └────────────┬───────────────────────────┘  │   │
│  │               │ Tauri IPC (invoke)             │   │
│  └───────────────┼──────────────────────────────┘   │
│                  │                                   │
│  ┌───────────────┴──────────────────────────────┐   │
│  │              Rust Backend                      │   │
│  │                                                │   │
│  │  AppState { client, sync_manager }             │   │
│  │       │                                        │   │
│  │  ├── proxy_request() ──────► reqwest::Client  │   │
│  │  │                            (cookie jar)     │   │
│  │  ├── AuthManager ───────────► SRP + API auth   │   │
│  │  ├── LiveSyncManager                           │   │
│  │  │    ├── notify::RecommendedWatcher            │   │
│  │  │    └── known_files suppression cache        │   │
│  │  └── save_download() ──────► ~/Downloads       │   │
│  └────────────────────────────────────────────────┘   │
│                                                       │
│  Plugins: shell, dialog, notification                 │
└─────────────────────────────────────────────────────┘
```

---

## 13. Build Configuration

- **Frontend dist:** `WebClients/applications/drive/dist` (built by `scripts/build-webclients.sh`)
- **Bundles:** `deb`, `rpm`, `appimage` (built by `npm run build` or individual `build:deb`/`build:rpm`/`build:appimage`)
- **Minimum Node:** `>=20.0.0`
- **Build-time env:** `DISTRO_TYPE` controls WebKit worker compatibility (see §8)
- **Run-time env vars:** `WEBKIT_DISABLE_DMABUF_RENDERER=1`, `WEBKIT_DISABLE_COMPOSITING_MODE=1`, `WEBKIT_FORCE_SANDBOX=0`, `GDK_GL=disable`, `GSK_RENDERER=cairo`

## See Also

- **[WebView Integration](../webview/webview-integration.md)** — How the WebView connects to all subsystems
- **[Sync System](../sync/sync-system.md)** — Full sync pipeline from kernel events to remote apply
- **[SSO Authentication](../auth/sso-authentication.md)** — End-to-end auth flow and cookie bridge
- **[Proxy System](proxy-system.md)** — Fetch/XHR interception architecture
- **[Build System](build-system.md)** — Cargo features, platform build matrix
- **[CI Pipeline Reference](../ci-cd/ci-pipeline-reference.md)** — CI jobs, artifacts, release workflow
- **[Sync DB Module](../sync/sync-db-module.md)** — AppState wiring, SyncKeyring, persistence
