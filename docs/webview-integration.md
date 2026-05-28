# WebView Integration

> How the Tauri v2 native shell integrates with Proton's web application (WebClients
> Drive).

## Overview

protondrive-linux wraps Proton's [WebClients](https://github.com/ProtonMail/WebClients)
Drive SPA in a Tauri v2 `WebviewWindow`. The application serves the Drive UI from a
locally built frontend bundle located at:

```
../WebClients/applications/drive/dist/
```

(relative to `src-tauri/`), configured via `frontendDist` in `src-tauri/tauri.conf.json`. The WebView loads
`index.html` (a thin shell) which bootstraps the React-based Drive application
(`index.tsx`). All UI rendering, routing, and business logic runs inside the WebView
via standard browser APIs. The Rust backend supplements the web app with native
capabilities: HTTP proxy, file downloads to the local filesystem, live sync, and
system notifications.

### Architecture

```
┌──────────────────────────────────────────────┐
│  Tauri WebviewWindow ("main")                 │
│  ┌──────────────────────────────────────────┐ │
│  │  Proton Drive SPA (WebClients)           │ │
│  │  tauri://localhost                       │ │
│  │                                          │ │
│  │  ┌──────────────────────────────────────┐│ │
│  │  │ Initialization Script (injected)     ││ │
│  │  │ ┌────────────────────────────────────┐││ │
│  │  │ │ Worker override (per distro)      │││ │
│  │  │ │ Console redirect → Rust            │││ │
│  │  │ │ fetch/XHR → proxy_request IPC      │││ │
│  │  │ │ Blob download interception         │││ │
│  │  │ │ CAPTCHA flow management            │││ │
│  │  │ │ URL rewriting (SSO)               │││ │
│  │  │ └────────────────────────────────────┘││ │
│  │  │ ┌──────────────────────────────────┐  │ │
│  │  │ │ window.__TAURI__ IPC bridge     │  │ │
│  │  │ └──────────────────────────────────┘  │ │
│  │  └──────────────────────────────────────┘ │
│  └──────────────────────────────────────────┘ │
│                                               │
│  Rust Backend (src-tauri/src/main.rs)          │
│  ┌──────────────────────────────────────────┐ │
│  │ AppState: reqwest::Client + cookie jar   │ │
│  │ LiveSyncManager                          │ │
│  │ Tauri Commands:                          │ │
│  │  · proxy_request → proxies API calls     │ │
│  │  · save_download → file system writes    │ │
│  │  · navigate_to_captcha → verif. flow    │ │
│  │  · store_* / get_and_clear_* (zero-trust)│ │
│  │  · start_sync / stop_sync / status      │ │
│  └──────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

## Key Configuration

| Setting | Value | Notes |
|---|---|---|
| Tauri version | 2.x (`"2.0"` Cargo dep) | `protocol-asset` feature enabled |
| `withGlobalTauri` | `true` | Exposes `window.__TAURI__` to frontend |
| CSP | Configured (allows `unsafe-inline`/`unsafe-eval`) | Required for Proton SPA inline scripts |
| DevTools | enabled (`devtools: true`) | Right-click → Inspect available |
| Frontend origin | `tauri://localhost` | Custom protocol (`custom-protocol` feature) |
| WebView backend | WebKitGTK (Linux) | WebKit2GTK 4.1 required |

### Tauri plugins

- `tauri-plugin-shell` — `open: true` (external URL handling)
- `tauri-plugin-dialog` — native file dialogs
- `tauri-plugin-notification` — system notifications

## Cookie Handling

Proton Drive's session management relies on session cookies (AUTH-*, REFRESH-*)
set during the SRP authentication flow. The Rust proxy reads and writes these
cookies directly to/from WebKit's **native cookie manager**, so WebKit handles
all cookie lifecycle — expiry, domain matching, Secure/HttpOnly flags — exactly
as a browser would.

### How it works

1. **On every proxied request**, `combined_cookie_header()` merges cookies from
   two sources:
   - **WebKit's native jar** via `webview.cookies_for_url(url)` — this is where
     session cookies live after login
   - **reqwest's in-process cookie jar** via `client_cookie_jar.cookies(url)` —
     used as a secondary source for freshly-set cookies that haven't been persisted
     to WebKit yet
   
   Client-jar cookies take precedence (last-write-wins) because they contain the
   freshest auth state immediately after login/2FA responses.

2. **On every proxied response**, `store_webview_cookie()` routes each
   `Set-Cookie` header into WebKit's native cookie manager via
   `window.set_cookie(cookie)`. It handles:
   - **Missing Path** — computes RFC-6265 §5.1.4 default-path (longest prefix of
     the request URI path ending in `/`)
   - **Missing Domain** — scopes the cookie to the response host so it survives
     app restarts (Tauri's `set_cookie` API doesn't receive the response URL
     separately; without an explicit domain a host-only cookie can't be matched on
     the next launch)
   - **Legacy cleanup** — when a correctly-scoped AUTH/REFRESH cookie is stored on
     `mail.proton.me`, older builds' blank-domain and host-only cookies are deleted
     to prevent ambiguous cookie state on restart

3. **The cookie header is excluded** from forwarded request headers
   (`k != "cookie"`) — the proxy injects its own merged cookie header instead,
   ensuring the correct auth context.

This means cookies live entirely in WebKit, not in Rust. The reqwest cookie jar
serves as a transient cache for the hot path (immediately after Set-Cookie
arrives), but WebKit is the source of truth.

### Module: `webview_cookies.rs`

The cookie integration is implemented in its own dedicated module (329 lines):

| Function | Purpose |
|----------|---------|
| `webview_cookie_header()` | Reads cookies from WebKit's native jar for a URL |
| `combined_cookie_header()` | Merges WebKit + reqwest cookies; client-jar wins on conflict |
| `store_webview_cookie()` | Routes a Set-Cookie header to WebKit, with domain/path fixing and legacy cleanup |
| `apply_default_cookie_scope()` | Sets Path (RFC-6265) and Domain (restart-persistence fix) |
| `legacy_blank_domain_delete_cookies()` | Identifies and deletes stale blank-domain AUTH/REFRESH cookies |
| `merge_cookie_headers()` | Merges two Cookie header strings, deduplicating by cookie name |

## Storage Bridge

There is **no** explicit Rust-to-JavaScript bridge for `localStorage` or
`sessionStorage`. The Proton WebClients SPA accesses the WebView's native
`localStorage` and `sessionStorage` directly through standard browser APIs, just
as it would in a regular browser.

The only storage-related code in the initialization script is diagnostic logging
that dumps `localStorage` keys prefixed with `ps-` (Proton session keys) on page
load:

```javascript
const allKeys = Object.keys(localStorage);
const sessionKeys = allKeys.filter(k => k.startsWith('ps-'));
console.log('[STORAGE] sessions:', sessionKeys.join(',') || 'none');
```

Because `withGlobalTauri` is `true`, the frontend can persist application state
(auth sessions, preferences, cached data) to the WebView's `localStorage` with
the same guarantees as a normal browser context.

## URL Interception and Navigation Logging

The WebView uses Tauri's `on_navigation` callback to intercept and rewrite all
page navigations. Every navigation event is logged to stdout with the
`[Navigation]` prefix.

### URL Rewriting Rules

| Incoming URL | Action | Target |
|---|---|---|
| `/login*` | Rewrite to local SSO | `tauri://localhost/account/?product=drive` |
| `account.proton.me/*` | Rewrite to local | `tauri://localhost/account/...` |
| `drive.proton.me/*` | Rewrite to local | `tauri://localhost/...` |
| `account.localhost/u/X/drive/...` | Login complete, redirect to Drive | `tauri://localhost/u/X/` |
| `blob:` URLs | Intercept and download via `save_download` | Local filesystem |
| `/api/*` | Blocked | API calls must use proxy (fetch/XHR), not navigation |
| `hcaptcha.com/*` | Allowed | Required for CAPTCHA widget |
| `verify.proton.me/*` | Allowed | CAPTCHA top-level page |
| `mail.proton.me/captcha/*` | Allowed | Legacy CAPTCHA pages |

### Navigation-inferred CAPTCHA lifecycle

The `on_navigation` callback tracks CAPTCHA state via an atomic boolean
(`ON_CAPTCHA_PAGE`). When a navigation enters a CAPTCHA-related URL
(`verify.proton.me`, hCaptcha, or Proton captcha endpoints), the flag is set.
While on the CAPTCHA page, internal navigations (about:blank, verify-api
requests) are allowed through. Completion is detected when the WebView
navigates to `tauri://localhost/account/?hv_token=...&hv_type=...` —
`captcha_completion_token()` parses these query parameters, stores the token
in `PENDING_VERIFICATION`, and navigates back to the account app to retry
authentication. If the WebView navigates back to `tauri://localhost/account/`
*without* `hv_token` params while `ON_CAPTCHA_PAGE` is true, the navigation is
blocked (ignored) to prevent premature auth retries.

### Download Blob Interception

The initialization script replaces `URL.createObjectURL`, `window.open`,
anchor click handlers, and `HTMLAnchorElement.prototype.download` to capture
blob URLs generated by Proton's download logic. When a blob URL is navigated or
clicked, the script extracts the `ArrayBuffer`, serializes it to bytes, and
invokes `save_download` to write it to `~/Downloads/`.

## Authentication Flow

The WebView interacts with Proton's authentication system through a sequence of
coordinated Rust and JavaScript components:

1. **SRP login** — The `AuthManager` (in `auth.rs`) handles the cryptographic
   SRP exchange with Proton's API. Successful authentication produces an
   `AuthSession` (UID + access token + refresh token).

2. **2FA handling** — If the account requires two-factor authentication, the
   flow pauses and the frontend prompts for a TOTP code. The
   `submit_2fa` method sends the code to Proton's `/api/auth/v4/2fa` endpoint.

3. **CAPTCHA / human verification** — If Proton returns error code 9001, the
   frontend's fetch proxy detects it:

   - Saves any login credentials from the page into Rust memory (zero-trust,
     single-use).
   - Calls `navigate_to_captcha(captcha_url, return_url)` which stores the
     return URL and navigates the entire WebView to the CAPTCHA page.
   - hCaptcha requires a top-level navigation in WebKitGTK — iframes do not
     render correctly.
   - On completion, the WebView returns to `tauri://localhost/account/?hv_token=...&hv_type=...`.
     The `on_navigation` callback detects this via `captcha_completion_token()`
     (which parses query params `hv_token` and `hv_type`), stores the token in
     `PENDING_VERIFICATION`, and navigates back to `tauri://localhost/account/`.
   - Saved credentials are auto-filled into the login form and submitted.
     The auth API call includes `x-pm-human-verification-token` and
     `x-pm-human-verification-token-type` headers (from `get_and_clear_verification_token`)
     to satisfy the verification requirement.

4. **Token refresh** — `AuthManager::refresh_token` obtains a new access token
   without user interaction.

5. **Session persistence** — The `AuthSession` struct is serializable and
   intended to be persisted to secure storage, though the current
   implementation relies on the in-memory session.

## Distro-Compatibility Worker Override

Different Linux distributions ship different WebKitGTK builds with varying
support for `Web Workers` and `Shared Workers`. The initialization script
handles this at build time via the `DISTRO_TYPE` environment variable:

| Build type | Action | Reason |
|---|---|---|
| `appimage`, `aur` | No override | Bundled WebKitGTK supports Workers |
| `rpm`, `deb`, `flatpak`, `snap` | Set `Worker = undefined` | System WebKitGTK throws "operation is insecure" |
| Unknown / unset | Stub Worker constructors that throw | Safe default for untested distros |

When Workers are disabled, Proton WebClients automatically falls back to
main-thread crypto (detected in
`packages/shared/lib/helpers/setupCryptoWorker.ts`).

## Security Considerations

### CSP

A Content Security Policy is configured in `tauri.conf.json` allowing
`'unsafe-inline'` and `'unsafe-eval'` to support Proton's SPA requirements:

```
default-src 'self' ipc: asset: https: blob: data:;
connect-src ipc: https: blob: data: 'self';
script-src 'self' 'unsafe-inline' 'unsafe-eval';
style-src 'self' 'unsafe-inline';
img-src 'self' data: blob: https:;
font-src 'self' data: https:;
worker-src 'self' blob:;
media-src 'self' blob: https:
```

This provides some baseline protection while allowing Proton's inline scripts,
dynamic resource loading, IPC communication (`ipc:`), and blob URL usage.

### Command origin gating

The `ensure_sync_command_allowed` function validates that sync-related Tauri
commands (`start_sync`, `stop_sync`, `get_sync_status`, `handle_remote_update`)
are only callable when the WebView's current origin matches
`tauri://localhost` or `tauri://tauri.localhost`. This prevents CAPTCHA pages
(served from `verify.proton.me`) from interacting with the sync system.

### Zero-trust token storage

- Verification tokens and login credentials are stored in raw `Mutex`
  singletons with no persistence.
- Each token is consumed on first read (`get_and_clear_*` returns `take()`
  which atomically clears the stored value).
- Credentials are never written to disk.

### Path sanitization for downloads

Download file paths are constructed from the URL's last path segment, with
query parameters stripped. The file is always written under `~/Downloads/`
with no path traversal check (the directory is hardcoded).

### Sync root validation

The `validate_sync_root_path` function ensures the sync root directory:
- Exists and can be canonicalized.
- Resides under the user's home directory.

### API navigation is blocked

The `on_navigation` callback blocks any navigation to `/api/*` paths, forcing
API calls through the proxy mechanism. This prevents the WebView from leaking
cookies via direct API navigations.

### DevTools are enabled

`devtools: true` is set on the `WebviewWindowBuilder`, meaning any user can
open a DevTools panel (right-click → Inspect). This aids debugging but
exposes the application internals.

### WebKitGTK hardening

The application starts with several environment variables to work around
WebKitGTK rendering issues on Linux:

```rust
std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
std::env::set_var("WEBKIT_FORCE_SANDBOX", "0");
std::env::set_var("GDK_GL", "disable");
std::env::set_var("GSK_RENDERER", "cairo");
```

Note: `WEBKIT_FORCE_SANDBOX=0` disables WebKit's sandbox, which reduces
process isolation.

## IPC Commands Registered

| Command | Parameters | Purpose |
|---|---|---|
| `proxy_request` | `{method, url, headers, body}` | Proxies HTTP requests through the shared cookie-authenticated client |
| `js_log` | `msg` | Forwards JavaScript console output to Rust stdout |
| `navigate_to_captcha` | `{captcha_url, return_url}` | Navigates the main WebView to a CAPTCHA verification URL |
| `get_captcha_return_url` | — | Returns the stored CAPTCHA return URL |
| `store_verification_token` | `{token, token_type}` | Stores a human-verification token in Rust memory (single-use) |
| `get_and_clear_verification_token` | — | Retrieves and clears the stored verification token |
| `store_login_credentials` | `{username, password}` | Temporarily stores login credentials during CAPTCHA flow |
| `get_and_clear_login_credentials` | — | Retrieves and clears stored credentials |
| `save_download` | `{filename, data}` | Writes a byte array to `~/Downloads/{filename}` |
| `start_sync` | `path` | Starts live-syncing a local directory with Proton Drive |
| `stop_sync` | — | Stops the active live-sync operation |
| `get_sync_status` | — | Returns the current sync manager status |
| `set_sync_root` | `path` | Sets the sync root and starts (or restarts) sync |
| `handle_remote_update` | `change` | Applies a remote Proton Drive change to the local sync root |
| `read_sync_file` | `{root_path, relative_path}` | Reads a file from the sync root for upload (base64 payload) |
| `get_sync_device_name` | — | Returns the sanitized machine hostname for Proton's Computers section |

## Source Files

| File | Purpose |
|---|---|
| `src-tauri/src/main.rs` | Tauri app entry point, WebView setup, proxy, commands, initialization script |
| `src-tauri/src/auth.rs` | SRP authentication manager (login, 2FA, token refresh, session management) |
| `src-tauri/src/live_sync.rs` | Live filesystem sync manager (watcher, poller, remote apply, suppression) |
| `src-tauri/src/sync_db.rs` | SQLite-backed sync metadata store (privacy-hashed, WAL mode) |
| `src-tauri/src/webview_cookies.rs` | WebKit cookie integration (read, merge, store, legacy cleanup) |
| `src-tauri/src/proton_navigation.rs` | URL rewriting (SSO, CAPTCHA completion, unsupported app redirects) |
| `src-tauri/src/webview_storage.rs` | Persistent WebView data directory |
| `src-tauri/src/url_log.rs` | URL sanitization for log output |
| `src-tauri/tauri.conf.json` | Tauri app configuration (window, build, bundle, plugins) |

## Troubleshooting

### Blank White Window

**Symptoms:** The app window opens but shows a blank white screen — no Proton Drive interface.

**Causes:**
- WebKitGTK rendering issue — GPU driver incompatibility
- The `tauri://localhost` custom protocol isn't registered
- The frontend build (`dist/`) is missing or empty
- WebKit sandbox blocks the custom protocol

**Fix:**
1. Verify the GPU env vars are set (the app sets them at startup — run from terminal to confirm)
2. Check the custom protocol: `grep -r "custom-protocol" src-tauri/Cargo.toml` — must be enabled
3. Verify `dist/` exists and contains the built frontend: `ls dist/index.html`
4. Try running with `WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11` to force software rendering
5. Check console for errors: Right Click > Inspect Element (requires developer tools)

### GPU Rendering Artifacts

**Symptoms:** Visual glitches — flickering, garbled text, black rectangles, color corruption.

**Causes:**
- GPU driver incompatibility with WebKitGTK's DMA-BUF buffer sharing
- Hardware compositing on a buggy driver (common on older NVIDIA and some AMD cards)
- Wayland compositor issues (the app uses `GDK_GL=disable` and `GSK_RENDERER=cairo` but some compositors override)

**Fix:**
The app already sets five env vars to mitigate this (`WEBKIT_DISABLE_DMABUF_RENDERER=1`, `WEBKIT_DISABLE_COMPOSITING_MODE=1`, etc.). If artifacts persist:
```bash
# Force X11 backend (bypass Wayland entirely)
GDK_BACKEND=x11 ./proton-drive

# Force software rendering
LIBGL_ALWAYS_SOFTWARE=1 ./proton-drive

# Disable GPU acceleration entirely
WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_GL=disable GSK_RENDERER=cairo ./proton-drive
```

### IPC Bridge Broken (Tauri Commands Not Responding)

**Symptoms:** UI shows "Connecting..." forever. No sync commands work. Console shows `TypeError: window.__TAURI__ is undefined`.

**Causes:**
- The Tauri IPC bridge failed to initialize
- `WEBKIT_FORCE_SANDBOX=1` blocks the IPC communication channel
- The init script didn't inject or ran too late
- WebKitGTK version is too old (< 2.40)

**Fix:**
1. Verify `WEBKIT_FORCE_SANDBOX=0` is set (the app sets it at startup)
2. Check WebKitGTK version: `pkg-config --modversion webkit2gtk-4.1` — must be ≥ 2.40
3. Restart the app — IPC initialization is a one-shot at startup
4. Check the console for early errors (before page load)

### WebView Crashes (SIGSEGV)

**Symptoms:** The app crashes with a segmentation fault. Backtrace points to WebKitGTK internals.

**Causes:**
- WebKitGTK bug triggered by a specific Proton page or Web API
- Memory corruption from GPU driver (NVIDIA proprietary drivers are common culprits)
- Out of memory — WebKitGTK can use 500MB+ for the Proton Drive SPA

**Fix:**
1. Update WebKitGTK to the latest version
2. Try the software rendering workarounds above
3. Check memory usage: `htop` or `ps aux | grep proton` — if RSS > 1.5GB, memory pressure may cause crashes
4. Get a backtrace: `coredumpctl dump` or `gdb ./proton-drive`

## See Also

- **[Proxy System](proxy-system.md)** — Fetch/XHR proxy layer, request interception, error handling
- **[Auth Module](auth-module.md)** — Session lifecycle, cookie management, logout flow
- **[SSO Authentication](sso-authentication.md)** — End-to-end SSO, CAPTCHA, cookie bridge protocol
- **[Proton Navigation](proton-navigation.md)** — URL rewriting, SSO routing
- **[Blob Downloads](blob-downloads.md)** — File download pipeline through the WebView bridge
- **[Architecture](ARCHITECTURE.md)** — How the WebView fits into the overall AppState
