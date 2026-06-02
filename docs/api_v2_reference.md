# ProtonDrive Linux v2 API Reference

## Overview
This document provides a concise reference for the **v2** REST endpoints and the native event‑driven (Tauri event) API used by the ProtonDrive Linux client. The client talks to Proton's backend APIs (auth, core, drive) via a native HTTP proxy (`proxy_request`) and emits internal Tauri events for file sync.

---

## Common Headers

All API calls made by the native client include:

| Header | Value | Used by |
|--------|-------|---------|
| `x-pm-appversion` | `web-drive@5.0.0` | All endpoints |
| `x-pm-uid` | The user's UID string | Authenticated endpoints |
| `Authorization` | `{TokenType} {AccessToken}` | Authenticated endpoints (e.g. `Bearer ...`) |
| `x-pm-human-verification-token` | Captcha/hV token | `/api/core/v4/auth` after captcha |
| `x-pm-human-verification-token-type` | `captcha` (or other hV type) | `/api/core/v4/auth` after captcha |
| `Content-Type` | `application/json` | POST endpoints |

Auth cookies (scoped to `/api/` path):
- `AUTH-uid` — session UID cookie
- `REFRESH-uid` — refresh token cookie

---

## Proton API Response Convention

All Proton API responses include a `Code` field (PascalCase in JSON):

| Code | Meaning |
|------|---------|
| **1000** | Success |
| **9001** | Human verification required — `Details` contains `HumanVerificationToken` and optional `WebUrl` for `verify.proton.me` |

---

## REST Endpoints

### Auth Endpoints (native client — `src-tauri/src/auth.rs`)

| Method | Path | Description | Request Body | Response Fields | Typical Errors |
|--------|------|-------------|--------------|-----------------|----------------|
| **POST** | `/api/auth/v4/info` | Fetch SRP parameters for a user (step 1 of login). | `{"Username":"user@example.com"}` | `Code`, `Modulus`, `ServerEphemeral`, `Version`, `Salt`, `SRPSession` | `400` (invalid username), `422` with `Code:9001` (human verification required) |
| **POST** | `/api/auth/v4` | Primary login — submit SRP proofs (step 2 of login). | `{"Username":"…","ClientEphemeral":"…","ClientProof":"…","SRPSession":"…"}` | `Code`, `UID`, `AccessToken`, `RefreshToken`, `TokenType`, `ServerProof`, `2FA` (optional: `Enabled`, `TOTP`) | `400` (bad request), `401` (invalid credentials) |
| **POST** | `/api/auth/v4/2fa` | Submit TOTP two‑factor code. | `{"TwoFactorCode":"123456"}` | Session established (same tokens from step 2). | `400` (missing code), `401` (invalid code) |
| **POST** | `/api/auth/v4/refresh` | Refresh session using stored refresh token. | `{"UID":"…","RefreshToken":"…","ResponseType":"token","GrantType":"refresh_token","RedirectURI":"https://proton.me"}` | `Code`, `AccessToken`, `RefreshToken`, `TokenType` | `401` (expired token) |
| **DELETE** | `/api/auth/v4` | Revoke the current session (logout). | _none_ | `200 OK` | `401` (not authenticated) |

> **Important:** The login flow uses Proton's SRP protocol — the client does **not** send plaintext passwords. The flow is: (1) `POST /api/auth/v4/info` with username → get SRP params, (2) compute proofs locally with `proton-srp`, (3) `POST /api/auth/v4` with SRP proofs → get session tokens, (4) if `2FA.Enabled != 0`, call `POST /api/auth/v4/2fa`.

### Core Endpoints (proxied via WebView — `src-tauri/src/main.rs`)

| Method | Path | Description | Notes | Typical Errors |
|--------|------|-------------|-------|----------------|
| **POST** | `/api/core/v4/auth` | Core auth handshake (account-side). The JS proxy injects `x-pm-human-verification-token` headers when a pending captcha token exists. | Must match this path exactly — NOT `/auth/cookies` or `/auth/info`. | `403` (blocked), `422` with `Code:9001` (human verification required) |
| **GET** | `/api/core/v4/captcha` | Captcha verification page. The client navigates to `verify.proton.me` as a top-level document; this path is also used to detect and block captcha iframe loads. | This is a browser navigation target, not a JSON API call. | N/A |

### Drive Endpoints (proxied via WebView)

> **Note:** The native client does not currently call any `/api/drive/v2/` endpoints directly. All Drive API interactions go through the WebView's JavaScript (WebClients) via the `proxy_request` Tauri command. The following endpoints are listed as proxied paths the client is aware of but does not call natively:

| Path | Status |
|------|--------|
| `/api/drive/v2/shares/photos` | Proxied through WebView — not called by native code |
| `/api/drive/v2/volumes/.../links` | Proxied through WebView — not called by native code |

---

## Human Verification (Captcha) Flow

1. Any authenticated API call may return `422 Unprocessable Entity` with `Code: 9001` and `Details.HumanVerificationToken` (plus optional `Details.WebUrl`).
2. The client navigates to `verify.proton.me` (or the `WebUrl`) as a top-level document — captcha iframes are blocked because hCaptcha requires top-level context in WebKitGTK.
3. hCaptcha completion sends a `pm_captcha` postMessage event with the solution token.
4. The token is stored in memory via the `store_verification_token` Tauri command (zero-trust — cleared after use).
5. On the next `POST /api/core/v4/auth` call, the JS proxy automatically injects `x-pm-human-verification-token` and `x-pm-human-verification-token-type` headers.
6. The auth call succeeds and the captcha flow is complete.

---

## Event‑Driven API (Tauri Events)

ProtonDrive Linux uses **Tauri events** for sync communication between the native Rust layer and the WebView frontend.

### 1. `live-sync://local-change`
**Direction:** Client (Rust) → Front‑end (WebClients)

**Payload (JSON, snake_case keys):**
```json
{
  "kind": "create|modify|remove",
  "paths": ["/absolute/path/to/file"],
  "root_path": "/home/user/ProtonDrive",
  "relative_paths": ["subdir/file.txt"],
  "source": "watcher|poller"
}
```
**When emitted:**
- After a filesystem event is caught by `notify` (watcher) **or** by the periodic poller (`DEFAULT_SYNC_POLL_INTERVAL` = 30s).
- The event is filtered through a suppression cache (TTL 30s, max 4096 entries) to avoid ping‑pong loops.

**Consumer:** The JavaScript `ProtonDriveLinuxSyncBridge` in WebClients reads the payload and queues uploads via the Proton SDK.

### 2. `handle_remote_update(change)`
**Direction:** Front‑end → Client (Rust)

The front‑end calls the exposed Tauri command `handle_remote_update(change)` where `change` matches the `RemoteSyncChange` struct (serialized as **camelCase**):

```json
{
  "relativePath": "subdir/file.txt",
  "action": "create|update|delete",
  "contentBase64": "..."
}
```

- `contentBase64` is **required** for `create` and `update` actions (the native side returns an error if missing).
- The native side validates the path (rejects `..`, absolute paths, symlinks), writes or deletes the file under the sync root, and adds the path to the suppression cache so the subsequent local‑change event is ignored.

---

## Tauri Command Surface

The client exposes these Tauri commands (invoked from JS via `window.__TAURI__.core.invoke`):

| Command | Description |
|---------|-------------|
| `proxy_request` | Proxy all `/api/` HTTP calls through the native client |
| `start_sync(path)` | Start recursive filesystem watcher + poller |
| `stop_sync` | Stop watcher and poller, clear suppression state |
| `get_sync_status` | Report sync status: `enabled` (bool), `folderPath` (Option<String>), `pollIntervalSeconds` (u64) |
| `set_sync_root(path)` | Persist and start sync for a new root directory |
| `handle_remote_update(change)` | Apply a remote sync change to the local filesystem |
| `read_sync_file(rootPath, relativePath)` | Zero-trust local file read for upload (max 100MB) |
| `get_sync_device_name` | Return the sanitized Linux device name |
| `navigate_to_captcha(captchaUrl, returnUrl)` | Navigate to captcha verification page |
| `get_captcha_return_url` | Retrieve and clear the stored captcha return URL (`Option<String>`) |
| `store_verification_token(token, tokenType)` | Store captcha solution token in memory |
| `get_and_clear_verification_token` | Retrieve and clear the stored captcha token |
| `store_login_credentials(username, password)` | Temporarily store credentials during captcha flow |
| `get_and_clear_login_credentials` | Retrieve and clear stored login credentials |
| `save_download(filename, data)` | Save a file to ~/Downloads |
| `js_log(msg)` | Forward JS console output to Rust stdout |

---

## Common Error Codes (HTTP + Proton)

| Code | Meaning |
|------|---------|
| **400** | Bad request – missing/invalid parameters. |
| **401** | Unauthorized – missing or expired auth token. |
| **403** | Forbidden – operation not allowed (e.g., navigation to `/api/` is blocked). |
| **404** | Not found – endpoint or resource does not exist. |
| **422** | Unprocessable entity – often `Code:9001` (human verification required). |
| **429** | Too many requests – rate limiting. |
| **500** | Internal server error – backend failure. |
| **502** | Bad gateway – native proxy request failed. |
| **504** | Gateway timeout – native proxy request timed out (45s). |

---

## How to Use This Reference
- **Developers** can use the curl examples below to test the endpoints against a live Proton backend (replace placeholders with real tokens).
- **Documentation writers** can expand each row with concrete request/response bodies once the official backend spec is available.
- **Test writers** can assert that the client emits `live-sync://local-change` with the exact payload shape defined above.

---

### Example `curl` for Auth Info (Step 1 of Login)
```bash
curl -X POST https://mail.proton.me/api/auth/v4/info \
  -H "Content-Type: application/json" \
  -H "x-pm-appversion: web-drive@5.0.0" \
  -d '{"Username":"user@example.com"}'
```

### Example `curl` for Login (Step 2 — SRP Proofs)
```bash
curl -X POST https://mail.proton.me/api/auth/v4 \
  -H "Content-Type: application/json" \
  -H "x-pm-appversion: web-drive@5.0.0" \
  -d '{"Username":"user@example.com","ClientEphemeral":"...","ClientProof":"...","SRPSession":"..."}'
```

### Example `curl` for Refresh
```bash
curl -X POST https://mail.proton.me/api/auth/v4/refresh \
  -H "Content-Type: application/json" \
  -H "x-pm-uid: ..." \
  -H "x-pm-appversion: web-drive@5.0.0" \
  -d '{"UID":"...","RefreshToken":"...","ResponseType":"token","GrantType":"refresh_token","RedirectURI":"https://proton.me"}'
```

---

*Reviewed and corrected by the Hermes Kanban worker for task **t_389ce507** — Docs review: protondrive-linux api_v2_reference.md (line-by-line).*
