# Proton Drive Navigation / Routing

> **Location:** `src-tauri/src/main.rs` — the navigation/routing logic is embedded in the `setup()` closure of the Tauri builder, not in a separate `proton_navigation.rs` module.
>
> **Why not a separate file:** Navigation interception is intrinsic to Tauri's window lifecycle. It lives in `main.rs` alongside the window builder, the initialization script injection, and the download event handler because all four (navigation, initialization, downloads, window config) are configured together on the same `WebviewWindowBuilder`.

## Overview

Proton Drive for Linux is a **Tauri v2** desktop application that loads the Proton Drive web client (`drive.proton.me`) inside a native WebView (WebKitGTK). Unlike a browser, a Tauri WebView does not have a natural URL bar, navigation controls, or cookie/session management integrated with a user's browser profile. The navigation/routing system bridges this gap by:

1. **Intercepting and rewriting** every URL navigation the WebView attempts
2. **Proxying API calls** from the web frontend through Tauri's native HTTP client (with cookie jar)
3. **Handling CAPTCHA / human verification** as top-level navigation (required by WebKitGTK)
4. **Redirecting blob downloads** to the native filesystem via `~/Downloads`

## Architecture

```
WebView (Proton Web Client)
    │
    ├── URL navigation ──→ on_navigation() callback ──→ rewrite / block / allow
    │
    ├── fetch() / XHR ──→ JS proxy (injected init script) ──→ proxy_request() Rust command
    │
    ├── Blob download ──→ JS blob interceptor ──→ save_download() Rust command
    │
    └── CAPTCHA flow ──→ postMessage listener ──→ navigate_to_captcha() Rust command
```

---

## 1. URL Routing (`on_navigation` callback)

The `on_navigation` closure (lines 1597–1803) is called by Tauri for **every URL the WebView attempts to navigate to**. It returns `true` to allow the navigation or `false` to block it (optionally redirecting elsewhere).

### 1.1 Blob URL Interception (Downloads)

```rust
if url.scheme() == "blob" { ... return false; }
```

**What:** When the Proton web client initiates a file download via `window.open('blob:...')` or `location.href = 'blob:...'`, this handler intercepts the blob navigation.

**How it works:**
- The JS initialization script (see §4) captures blob URLs created by `URL.createObjectURL()` into a `Map`.
- When the WebView attempts to navigate to a blob URL, the `on_navigation` callback:
  1. Gets the stored blob from the JS `__blobUrls` map via `eval()`
  2. Reads the blob as an `ArrayBuffer`
  3. Calls the `save_download` Rust command to write the file to `~/Downloads`
  4. Returns `false` to block the navigation (the download was handled natively)

### 1.2 SSO Login Rewrite (`/login` → `/account/`)

```rust
if url.path().starts_with("/login") { ... }
```

**What:** When the Proton web client navigates to a `/login` path, the handler rewrites it to the local SSO account app at `tauri://localhost/account/?product=drive`.

**Why:** Proton's SSO login is a separate web application. In a browser, clicking "Sign in" redirects you to `account.proton.me/login`. In the desktop app, this must be served locally. The handler:
- Strips `reason=` and `type=` query params (session-expired markers)
- Adds `product=drive` so the account app knows to redirect back to Drive after login
- Navigates the WebView to `tauri://localhost/account/...`

### 1.3 External Account Redirect (`account.proton.me` → local)

```rust
if url.host_str() == Some("account.proton.me") { ... }
```

**What:** If the Proton web client emits a navigation to the external `account.proton.me` domain (e.g. from a link or a redirect), the handler rewrites it to the local SSO app.

**How:** Preserves the path and query, rewrites `https://account.proton.me/path?q` → `tauri://localhost/account/path?q`.

### 1.4 External Drive Redirect (`drive.proton.me` → local)

```rust
if url.host_str() == Some("drive.proton.me") { ... }
```

**What:** Same pattern for any stray navigation to the production `drive.proton.me` domain — rewrites to the local `tauri://localhost/...` equivalent.

### 1.5 Post-Login Redirect (`account.localhost` → Drive)

```rust
if url.host_str() == Some("account.localhost") { ... }
```

**What:** After a successful SSO login, the account app navigates to `account.localhost/u/X/drive/account`. This handler:
1. Extracts the user path segment (`/u/X/`)
2. Navigates to `tauri://localhost/u/X/` (the Drive app)
3. Adds a 300ms delay to let cookies propagate before navigation

### 1.6 CAPTCHA / Verfication Domains

```rust
// hCaptcha resources: allow unconditionally
if host == "hcaptcha.com" || host.ends_with(".hcaptcha.com") { return true; }

// Proton verify domains
match url.host_str() {
    Some("mail.proton.me") if path starts with /api/core/v4/captcha or /captcha/ => ...
    Some("verify.proton.me") => true
    Some("verify-api.proton.me") => true
    ...
}
```

**What:** Certain external domains must be allowed through for the CAPTCHA widget to function:
- **hCaptcha.com** — serves the CAPTCHA widget assets
- **verify.proton.me** — the human verification page
- **verify-api.proton.me** — CAPTCHA content API
- **mail.proton.me/api/core/v4/captcha** — legacy captcha endpoints

Additionally, when the WebView navigates **away** from a captcha page, the handler redirects back to `tauri://localhost/account/` to retry authentication with the stored verification token.

### 1.7 API Navigation Blocking

```rust
if url.path().starts_with("/api/") { return false; }
```

**What:** Prevents the WebView from navigating to API endpoints directly (e.g. if an iframe tries to load `/api/core/v4/*`). API calls should go through the `fetch`/`XHR` proxy, not through URL navigation.

### 1.8 Default Allow Rules

```rust
url.scheme() == "tauri"
    || url.scheme() == "about"
    || url.host_str() == Some("localhost")
    || url.host_str() == Some("tauri.localhost")
```

**What:** All other navigations are allowed only if they are:
- `tauri://` protocol (local app pages)
- `about:` protocol (about pages)
- Hosted on `localhost` or `tauri.localhost` (local development / API)

Everything else (external HTTP(S) URLs, arbitrary schemes) is silently blocked.

---

## 2. HTTP Request Proxying

The web frontend cannot make direct HTTP requests to Proton's API because of CORS restrictions and the need for cookie-based session management. Instead, all API traffic is proxied through Tauri's native HTTP client.

### 2.1 `fetch()` Interception

> **Injected JS** — the initialization script overrides `window.fetch`.

When the web client makes a `fetch()` call to an API endpoint (`/api/` in the URL), the overridden handler:
1. Serializes headers and body
2. Checks for pending human-verification tokens and attaches them as `x-pm-human-verification-*` headers
3. Calls the `proxy_request` Rust Tauri command
4. Applies `Set-Cookie` headers from the response to the document's cookie store
5. Detects HTTP 422 / Code 9001 (CAPTCHA required) and triggers the captcha navigation flow

Non-API fetch calls (assets, images, etc.) pass through to the native `window.fetch` unchanged.

### 2.2 `XMLHttpRequest` Interception

> **Injected JS** — overrides `window.XMLHttpRequest`.

Same pattern as fetch but for XHR-based API calls. API calls are redirected through `proxy_request`; non-API calls use the native `XMLHttpRequest`.

### 2.3 `proxy_request` Rust Command

> **File:** `main.rs`, lines 386–510

```rust
#[tauri::command]
async fn proxy_request(state: ..., request: ProxyRequest) -> Result<ProxyResponse, String>
```

**URL Rewriting Logic:**

| Incoming URL Pattern | Rewritten To |
|---|---|
| `https://localhost/api/...` | `https://mail.proton.me/api/...` |
| `http://localhost/api/...` | `https://mail.proton.me/api/...` |
| `tauri://.../api/...` | `https://mail.proton.me/api/...` |
| `/api/...` | `https://mail.proton.me/api/...` |
| Plain URL | Appended to `https://mail.proton.me/` |

**Cookie Management:**
- The `reqwest::Client` is configured with `.cookie_store(true)`
- Cookies flow automatically through the shared cookie jar
- Response `Set-Cookie` headers are written directly to the WebView's native WebKit cookie manager via `store_webview_cookie()`, keeping the WebView and proxy client cookie state in sync

---

## 3. CAPTCHA / Human Verification Flow

Proton may require human verification (CAPTCHA / hCaptcha) during login or sensitive operations. In WebKitGTK, CAPTCHA widgets fail inside iframes — they must be rendered as a **top-level document**.

### 3.1 Trigger

1. The `fetch` proxy detects a 422 response with `Code === 9001` from the API
2. It saves the current login credentials (username/password) from the form fields
3. It calls `navigate_to_captcha()` with the verification URL from Proton's response

### 3.2 Navigation

The `navigate_to_captcha` Rust command (lines 143–166):
1. Stores the return URL in `CAPTCHA_RETURN_URL`
2. Navigates the main WebView window to the CAPTCHA URL (e.g., `https://verify.proton.me/...`)

### 3.3 Verification

1. The CAPTCHA page fires a `postMessage` with `type: 'HUMAN_VERIFICATION_SUCCESS'` (or `'pm_captcha'`) containing the verification token
2. The `message` event listener stores the token via `store_verification_token`
3. The listener navigates back to `tauri://localhost/account/`
4. The `on_navigation` callback detects the CAPTCHA page exit and ensures redirection back to the account app
5. The `fetch` proxy attaches `x-pm-human-verification-token` and `x-pm-human-verification-token-type` headers to the next auth request

### 3.4 Credential Restoration

When the account app page reloads after CAPTCHA, the injected JS:
1. Calls `get_and_clear_login_credentials()` to retrieve saved credentials
2. Fills them into the login form
3. Auto-submits after a 1.5s delay

All credential and token storage is **zero-trust** — cleared after a single use.

### 3.5 Iframe Blocking

The initialization script also blocks CAPTCHA iframes by overriding `HTMLIFrameElement.prototype.src` and `Element.prototype.setAttribute`. This prevents the web client from loading CAPTCHA in an iframe (which would appear broken/stuck in WebKitGTK) and forces top-level navigation instead.

---

## 4. Initialization Script (Client-Side Interception)

The Tauri `WebviewWindowBuilder` is configured with an `initialization_script` — a large JavaScript injection that runs before the web client loads. This script handles:

| Concern | Lines | Description |
|---|---|---|
| **Worker management** | 382–457 | Disables `Worker` / `SharedWorker` on distros with broken WebKitGTK Worker support (rpm, deb, flatpak, snap). AppImage/AUR builds use native Workers. |
| **Blob download tracking** | 464–574 | Captures `URL.createObjectURL()` calls, intercepts `window.open('blob:...')`, anchor clicks, and download attribute changes |
| **Console forwarding** | 716–747 | Redirects `console.log/error/warn` to Rust's `js_log` command for debug visibility |
| **CAPTCHA flow** | 577–713 | `postMessage` listener, iframe blocking, credential auto-fill |
| **Fetch/XHR proxy** | 749–946 | Overrides `window.fetch` and `window.XMLHttpRequest` to route API calls through Tauri |
| **Protocol-relative URL fix** | 754–759 | Converts `//assets/...` (invalid in `tauri://` context) to `/assets/...` |

---

## 5. Why Custom Navigation Handling Is Needed

| Challenge | Browser | Tauri Desktop App |
|---|---|---|
| **URL navigation** | User controls via address bar | Must be intercepted and rewritten |
| **Cookie/session** | Managed by browser profile | Must be proxied through reqwest cookie jar |
| **CAPTCHA/hCaptcha** | Works in iframes or popups | WebKitGTK requires top-level navigation |
| **Downloads** | Browser handles blob URLs natively | Must be intercepted, read as bytes, and saved to `~/Downloads` |
| **CORS** | Same-origin policy applies | WebView has no CORS for `tauri://` origin; requests must be proxied |
| **Web Workers** | Full support | WebKitGTK versions vary; some distros have broken Worker implementations |
| **SSO redirects** | Browser follows redirects naturally | Must be rewritten from `account.proton.me` → `tauri://localhost/account/` |
| **Console debugging** | Visible in DevTools | Must be forwarded to Rust's stdout via `invoke('js_log')` |

---

## 6. Distro-Specific Worker Handling

The initialization script applies **three strategies** depending on the build's `DISTRO_TYPE`:

| `DISTRO_TYPE` | Strategy | Rationale |
|---|---|---|
| `appimage` / `aur` | Leave Workers intact | Bundled WebKitGTK supports Workers correctly |
| `rpm` / `deb` / `flatpak` / `snap` | Set `Worker = undefined`, `SharedWorker = undefined` | System WebKitGTK has "operation is insecure" bug; Proton falls back to main-thread crypto |
| None / unknown | Stub Workers with error-throwing constructors | Safe default — blocks Worker usage and handles errors gracefully |

---

## 7. Command Registration

All navigation-related Tauri commands are registered via `generate_handler!`:

| Command | Purpose |
|---|---|
| `proxy_request` | Proxy HTTP requests through native client |
| `js_log` | Forward console logs from WebView to Rust |
| `navigate_to_captcha` | Navigate WebView to CAPTCHA URL |
| `get_captcha_return_url` | Retrieve the post-CAPTCHA return URL |
| `store_verification_token` | Store human-verification token |
| `get_and_clear_verification_token` | Single-use token retrieval |
| `store_login_credentials` | Save credentials during CAPTCHA flow |
| `get_and_clear_login_credentials` | Single-use credential retrieval |
| `save_download` | Write blob data to `~/Downloads` |

*Sync commands (`start_sync`, `stop_sync`, etc.) are documented in `docs/sync/sync.md`.*

## See Also

- **[SSO Authentication](sso-authentication.md)** — URL flow through SSO, CAPTCHA integration
- **[Proxy System](proxy-system.md)** — How navigation decisions interact with the fetch proxy
- **[WebView Integration](webview-integration.md)** — Tauri plugin wiring, IPC commands
- **[Architecture](ARCHITECTURE.md)** — How navigation fits into the AppState
