# WebView Integration

> How the Tauri v2 native shell integrates with Proton's web application (WebClients
> Drive).

## Overview

protondrive-linux wraps Proton's [WebClients](https://github.com/ProtonMail/WebClients)
Drive SPA in a Tauri v2 `WebviewWindow`. The application serves the Drive UI from a
locally built frontend bundle located at:

```
WebClients/applications/drive/dist/
```

configured via `frontendDist` in `src-tauri/tauri.conf.json`. The WebView loads
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
| CSP | `null` (disabled) | Security concern — wide-open |
| DevTools | enabled (`devtools: true`) | Right-click → Inspect available |
| Frontend origin | `tauri://localhost` | Custom protocol (`custom-protocol` feature) |
| WebView backend | WebKitGTK (Linux) | WebKit2GTK 4.1 required |

### Tauri plugins

- `tauri-plugin-shell` — `open: true` (external URL handling)
- `tauri-plugin-dialog` — native file dialogs
- `tauri-plugin-notification` — system notifications

## Cookie Handling

Proton Drive's session management relies on cookies set during the SRP authentication
flow. Because the WebView's built-in cookie jar is separate from the Rust backend's
HTTP client, cookies are injected manually.

### How it works

1. **Backend** — The Rust `reqwest::Client` is created with
   `cookie_store(true)`, so it automatically manages a cookie jar for all API
   requests sent through the `proxy_request` Tauri command.

2. **Proxy intercept** — When the frontend makes an API call (e.g.
   `/api/core/v4/auth`), the injected initialization script intercepts
   `window.fetch` and `XMLHttpRequest`, then sends the request through the
   backend via `window.__TAURI__.core.invoke('proxy_request', ...)`.

3. **Set-Cookie forwarding** — The backend's `proxy_request` function collects
   all `Set-Cookie` response headers into a list, joins them with the `|||`
   delimiter, and returns them as a single custom `x-set-cookie` header:

   ```rust
   let mut set_cookies: Vec<String> = Vec::new();
   for (name, value) in resp.headers().iter() {
       if name.as_str().eq_ignore_ascii_case("set-cookie") {
           set_cookies.push(v.to_string());
       }
   }
   resp_headers.insert("x-set-cookie".to_string(), set_cookies.join("|||"));
   ```

4. **Frontend injection** — The fetch proxy checks `response.headers['x-set-cookie']`,
   splits on `|||`, and writes each cookie into the WebView's `document.cookie`
   with `path=/; SameSite=Lax`:

   ```javascript
   if (response.headers && response.headers['x-set-cookie']) {
       const cookies = response.headers['x-set-cookie'].split('|||');
       for (const cookie of cookies) {
           const cookiePart = cookie.split(';')[0];
           document.cookie = cookiePart + '; path=/; SameSite=Lax';
       }
   }
   ```

5. **Cookie header is excluded** — The proxy deliberately skips the `cookie`
   header from forwarded requests (`k != "cookie"`), relying on the reqwest
   cookie jar to handle it automatically.

This approach ensures the WebView's `document.cookie` stays in sync with the
backend's cookie jar, which is essential for Proton's session decryption flow.

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
When a subsequent navigation leaves the CAPTCHA page, the flag triggers a
redirect back to the account app (`tauri://localhost/account/`) to retry
authentication with the newly obtained human-verification token.

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
   - Navigates the entire WebView to the CAPTCHA URL
     (`verify.proton.me` or `mail.proton.me/captcha/`).
   - hCaptcha requires a top-level navigation in WebKitGTK — iframes do not
     render correctly.
   - On completion, a `HUMAN_VERIFICATION_SUCCESS` or `pm_captcha` postMessage
     stores the verification token in Rust memory.
   - The WebView navigates back to `tauri://localhost/account/` where saved
     credentials are auto-filled and the auth request is retried with the
     verification token.

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

### CSP is disabled

The Content Security Policy is set to `null` in `tauri.conf.json`, meaning no
CSP restrictions are applied to the WebView. This is a known security concern
— any XSS vulnerability in the Proton SPA or injected scripts could be
exploited without CSP mitigation. (CSP cannot be trivially enabled because
Proton's SPA requires inline scripts and dynamic resource loading.)

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
| `handle_remote_update` | `change` | Applies a remote Proton Drive change to the local sync root |

## Source Files

| File | Purpose |
|---|---|
| `src-tauri/src/main.rs` | Tauri app entry point, WebView setup, proxy, commands, initialization script |
| `src-tauri/src/auth.rs` | SRP authentication manager (login, 2FA, token refresh) |
| `src-tauri/src/live_sync.rs` | Live filesystem sync manager |
| `src-tauri/tauri.conf.json` | Tauri app configuration (window, build, bundle, plugins) |
| `src-tauri/src/index.html` | WebView entry point — loads the React SPA |
