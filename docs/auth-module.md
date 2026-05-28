# Authentication Module

The protondrive-linux authentication system is split into two cooperating layers:

1. **Rust backend** (`auth.rs`) — SRP cryptographic login, session management, token refresh
2. **JS proxy layer** (`main.rs` initialization script) — API interception, cookie sync, CAPTCHA handling, SSO navigation

This document explains both layers and how they interact.

---

## 1. `auth.rs` — Rust SRP Authentication

**File:** `src-tauri/src/auth.rs`

The `auth` module implements Proton's SRP (Secure Remote Password) authentication protocol using the official [`proton-srp`](https://crates.io/crates/proton-srp) crate. It is designed as a standalone module; see **Integration Status** at the end of this section.

### Core Types

| Type | Role |
|------|------|
| `AuthManager` | Full lifecycle manager — login, session storage, token refresh, logout |
| `AuthSession` | Token triplet (`uid`, `access_token`, `refresh_token`, `token_type`) returned after a successful authentication |
| `AuthError` | Enum covering all failure modes |

### AuthError Variants

| Variant | Trigger |
|---------|---------|
| `Network(reqwest::Error)` | HTTP/transport failure |
| `Srp(String)` | SRP proof calculation or verification failed |
| `InvalidResponse(String)` | API returned unexpected or unparseable data |
| `TwoFactorRequired` | Server requested a TOTP code before granting access |
| `InvalidCredentials` | Wrong username/password or server-proof mismatch |
| `NotAuthenticated` | No session held — call `login()` or `set_session()` first |
| `HumanVerificationRequired` | Proton API returned error 9001; interactive CAPTCHA needed |

### AuthSession Fields

| Field | Purpose |
|-------|---------|
| `uid` | Proton user/session identifier, sent as `x-pm-uid` on every API request |
| `access_token` | Short-lived bearer token (~1 hour); sent as `Authorization: Bearer <token>` |
| `refresh_token` | Long-lived token for obtaining a new `access_token` without re-entering credentials |
| `token_type` | Usually `"Bearer"`; prepended to the `access_token` in the Authorization header |

### Login Flow (Step by Step)

```
┌──────────┐     ┌────────────┐     ┌──────────────┐
│  User    │     │ AuthManager│     │ Proton API    │
│(username │     │  (Rust)    │     │ mail.proton.me│
│,password)│     │            │     │               │
└────┬─────┘     └─────┬──────┘     └──────┬────────┘
     │ login(u, p)      │                   │
     │─────────────────>│                   │
     │                  │ POST /api/auth/v4/info
     │                  │──────────────────>│
     │                  │←─────────────────│ {modulus, server_ephemeral,
     │                  │                    │  version, salt, SRPSession}
     │                  │                   │
     │                  │ SRPAuth::with_pgp(password, version, salt,
     │                  │   modulus, server_ephemeral) → proofs
     │                  │                   │
     │                  │ POST /api/auth/v4  │
     │                  │──────────────────>│ {ClientEphemeral, ClientProof,
     │                  │                    │  SRPSession}
     │                  │←─────────────────│ {UID, access_token, refresh_token,
     │                  │                    │  token_type, server_proof}
     │                  │                   │
     │                  │ proofs.compare_server_proof(server_proof) ✓
     │                  │                   │
     │                  │ [ if 2FA enabled ]│
     │                  │ → return Err(TwoFactorRequired)
     │                  │ → store Pending2FA internally
     │                  │                   │
     │                  │ Store AuthSession
     │                  │─────────────────│ Ok(AuthSession)
     │                  │                   │
```

**Step 1 — Get SRP parameters:** `POST /api/auth/v4/info` with the username. The server returns the SRP modulus, server ephemeral, version, salt, and a session identifier.

**Step 2 — Calculate SRP proofs:** The [`proton-srp`](https://crates.io/crates/proton-srp) crate computes the client ephemeral and client proof from the password and server parameters. Uses the PGP variant (`SRPAuth::with_pgp`).

**Step 3 — Submit auth request:** `POST /api/auth/v4` with the username, client ephemeral, client proof, and SRP session.

**Step 4 — Verify server proof:** The server returns its own proof. The client verifies it cryptographically using `proofs.compare_server_proof()`. If this fails, the credentials are rejected with `InvalidCredentials` — this catches server impersonation or MITM attacks.

**Step 5 — Check for 2FA:** If the server indicates TOTP is enabled, the login pauses. The partial tokens are stored as `Pending2FA` internally, and `TwoFactorRequired` is returned to the caller.

**Step 6 — Store session:** On success, the `AuthSession` is stored in the in-memory `RwLock<Option<AuthSession>>`.

### 2FA Verification

After receiving a `TwoFactorRequired` error, call `submit_2fa(totp_code)`:

```rust
auth_manager.submit_2fa("123456").await?;
```

This sends `POST /api/auth/v4/2fa` with the TOTP code, using the pending session tokens. On success, the final `AuthSession` is stored and returned. The pending state is cleared.

### Token Refresh

`refresh_token()` obtains a new `access_token` without re-entering credentials:

```
POST /api/auth/v4/refresh
Body: { UID, RefreshToken, ResponseType: "token", GrantType: "refresh_token", RedirectURI: "https://proton.me" }
```

Uses the `refresh_token` from the current session. On success, both `access_token` and `refresh_token` are updated in memory.

### Session Persistence

The `AuthManager` stores sessions only in memory (`RwLock<Option<AuthSession>>`). Two methods support external persistence:

| Method | Purpose |
|--------|---------|
| `get_session() -> Option<AuthSession>` | Read the current session for serialization to disk |
| `set_session(AuthSession)` | Restore a previously serialized session on launch |

Callers are expected to persist `AuthSession` to secure storage (e.g., OS keychain, encrypted file) and restore it on startup.

### Logout

`logout()` sends `DELETE /api/auth/v4` to invalidate the session server-side, then clears the in-memory session. The HTTP request is best-effort (result is ignored) — local state is always cleared.

### Private Helpers

| Helper | Endpoint | Purpose |
|--------|----------|---------|
| `get_auth_info(username)` | `POST /api/auth/v4/info` | Fetches SRP parameters. Returns `HumanVerificationRequired` on error code 9001 |
| `submit_auth(username, client_ephemeral, client_proof, srp_session)` | `POST /api/auth/v4` | Submits SRP proofs. Validates `code == 1000` on success |

### Integration Status

> **Note:** As of the current codebase, `auth.rs` defines the authentication types and logic but is **not yet wired into the binary**. The file exists at `src-tauri/src/auth.rs` but no `mod auth;` declaration appears in `main.rs`, and `proton-srp` is not listed in `Cargo.toml` dependencies. The actual running application uses a different authentication flow: it loads the Proton WebClients frontend in a Tauri WebView and relies on the **proxy request system** (described below) to handle authentication transparently through the WebView's own login pages.

> When `auth.rs` is activated, it will provide native SRP login, session persistence to the OS keychain, and offline-first authentication — reducing reliance on the WebView-based login flow.

---

## 2. Proxy Request System — The Active Auth Layer

While `auth.rs` is planned for native auth, the current application authenticates by loading Proton's web-based account app (`tauri://localhost/account/`) in a WebView and proxying all API calls through a shared `reqwest::Client` with cookie support.

### Architecture

```
┌─────────────────────────────────────────────────┐
│                  Tauri WebView                    │
│  ┌────────────────────────────────────────────┐  │
│  │  Proton WebClients (account/drive)         │  │
│  │                                            │  │
│  │  fetch("/api/...") → intercepted by        │  │
│  │  window.fetch override                     │  │
│  │  ↓                                         │  │
│  │  window.__TAURI__.invoke("proxy_request")  │  │
│  └───────────────────────────┬────────────────┘  │
│                              │                    │
└──────────────────────────────┼────────────────────┘
                               │ IPC
┌──────────────────────────────┼────────────────────┐
│  Rust Backend                │                    │
│  ┌───────────────────────────┴────────────────┐   │
│  │  proxy_request(command)                    │   │
│  │  ↓                                         │   │
│  │  reqwest::Client (cookie_store=true)        │   │
│  │  ↓                                         │   │
│  │  Proton API (mail.proton.me)               │   │
│  │  ↓                                         │   │
│  │  Set-Cookie → store_webview_cookie()       │   │
│  │  (routes to WebKit native cookie manager)  │   │
│  └────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

### URL Rewriting

The `on_navigation` handler rewrites external Proton URLs to local `tauri://localhost/` URLs:

| External URL | Rewritten To |
|---|---|
| `https://account.proton.me/login` | `tauri://localhost/account/?product=drive` |
| `https://account.proton.me/...` | `tauri://localhost/account/...` |
| `https://drive.proton.me/...` | `tauri://localhost/...` |
| `/login` | `tauri://localhost/account/?product=drive` |
| `account.localhost/u/X/drive/...` | `tauri://localhost/u/X/` (post-login redirect) |

This ensures the WebView always loads the bundled WebClients assets from the local Tauri protocol, while the account app's SSO flow works as intended.

### Cookie Integration (WebView → Proton API)

The `proxy_request` Tauri command is the critical bridge:

1. **Frontend intercepts all API fetches/XHRs** via monkey-patched `window.fetch` and `XMLHttpRequest`
2. **API calls are sent** to the Rust backend via `invoke('proxy_request', { method, url, headers, body })`
3. **Rust rewrites localhost URLs** to the real Proton API (`https://mail.proton.me`)
4. **The shared reqwest client** forwards requests with cookies merged from both WebKit's native jar and the reqwest cookie jar (via `combined_cookie_header()`)
5. **Response `Set-Cookie` headers** are routed directly into WebKit's native cookie manager (via `store_webview_cookie()`) — WebKit handles all cookie lifecycle (expiry, domain, Secure/HttpOnly flags) exactly as a browser would
6. **Legacy cookie cleanup** — when a correctly-scoped AUTH/REFRESH cookie is stored on `mail.proton.me`, older builds' blank-domain and host-only cookies are automatically deleted

This WebKit-native cookie approach is important because Proton's WebClients frontend relies on cookie-bearing requests for session continuity. Unlike the older `x-set-cookie` approach that wrote cookies to `document.cookie`, the current implementation writes directly to WebKit's cookie manager — this is more reliable across app restarts and avoids race conditions between JavaScript's `document.cookie` and WebKit's native cookie store.

### CAPTCHA / Human Verification Flow

```
1. Proxy sends API request → Server returns 422 with Code: 9001
2. Fetch interceptor detects 9001 + HumanVerificationToken in response
3. Saves current login credentials from form (email + password) via
   `store_login_credentials` command
4. Navigates WebView to verify.proton.me (top-level, not iframe)
5. User completes hCaptcha challenge
6. POST_MESSAGE from verify page fires `HUMAN_VERIFICATION_SUCCESS`
7. Token stored via `store_verification_token` (single-use, zero-trust)
8. WebView navigates back to tauri://localhost/account/
9. Stored credentials retrieved via `get_and_clear_login_credentials`
10. Credentials auto-filled into the login form and submitted
11. Auth API call is retried — `get_and_clear_verification_token` adds
    `x-pm-human-verification-token` + `x-pm-human-verification-token-type`
    headers to prevent the 9001 from re-firing
```

### Web Worker Compatibility

Different Linux packaging formats have varying WebKitGTK Worker support:

| Distro Type | Web Worker Strategy |
|---|---|
| `appimage`, `aur` | Native Workers — no override needed |
| `rpm`, `deb`, `flatpak`, `snap` | `window.Worker = undefined` — forces Proton's main-thread crypto fallback |
| Unknown | `Worker` deleted and blocked with a stub — safe default |

This is controlled at build time via the `DISTRO_TYPE` environment variable.

---

## 3. Security Considerations

| Concern | Mitigation |
|---------|------------|
| Credential exposure | Login credentials are stored in memory-only static variables (PENDING_CREDENTIALS) and cleared after single use. Verification tokens similarly use single-use storage. |
| SRP protocol security | Uses the official `proton-srp` crate. Server proof is verified client-side to prevent MITM/impersonation. |
| Cookie theft | Cookies stored in `document.cookie` with `SameSite=Lax` and `path=/`. The shared reqwest cookie jar is in-memory only with no persistence. |
| Session storage | The `AuthManager` holds sessions in-memory only. External persistence must be implemented by the caller with appropriate encryption (OS keychain recommended). |
| Sync command isolation | Sync-related commands validate the caller's origin — only `tauri://localhost` and `tauri://tauri.localhost` are permitted (`ensure_sync_command_allowed`). |
| XSS surface | The fetch/XHR proxy intercept only applies to API URLs (`/api/` in path). Non-API requests pass through normally. |

---

## 4. Edge Cases

- **Token refresh failure during active use:** The `refresh_token()` method returns `InvalidCredentials` if the refresh fails. The caller should redirect to the login page.
- **2FA interrupted mid-flow:** `Pending2FA` state is lost on `AuthManager` drop. If the user does not complete 2FA, they must restart login from scratch.
- **CAPTCHA credential loss:** If the user navigates away during CAPTCHA, saved credentials in `PENDING_CREDENTIALS` persist until retrieved. Restarting the app clears them.
- **Multiple Set-Cookie headers:** Proton may send multiple `Set-Cookie` headers in one response. Each is routed individually to WebKit's cookie manager via `store_webview_cookie()`, which applies RFC-6265 path/domain scoping before calling `window.set_cookie()`.
- **blob: URL downloads:** Downloads initiated by the web app (via `window.open(blob:...)` or anchor clicks) are intercepted, read as `ArrayBuffer`, and saved to `~/Downloads` via the `save_download` command.
- **Navigation to `/api/` paths:** Blocked by `on_navigation` to prevent iframes from loading API endpoints as documents. API calls must go through the fetch proxy.
