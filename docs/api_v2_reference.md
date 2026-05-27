# ProtonDrive Linux v2 API Reference

## Overview
This document provides a concise reference for the **v2** REST endpoints and the native event‑driven (WebSocket‑style) API used by the ProtonDrive Linux client. The client talks to Proton's backend APIs (auth, core, drive) and emits internal events for file sync.

---

## REST Endpoints
| Method | Path | Description | Example Request | Example Response | Typical Errors |
|--------|------|-------------|-----------------|------------------|----------------|
| **POST** | `/api/auth/v4/2fa` | Submit two‑factor authentication code. | ```json {"TwoFactorCode":"123456"}``` | `200 OK` with auth cookies. | `400 Bad Request` (missing code), `401 Unauthorized` (invalid code) |
| **POST** | `/api/auth/v4/refresh` | Refresh session using stored refresh token. | ```json {"RefreshToken":"..."}``` | `200 OK` with new access token. | `401 Unauthorized` (expired token) |
| **DELETE** | `/api/auth/v4` | Revoke the current session (logout). | _none_ | `200 OK` | `401 Unauthorized` |
| **POST** | `/api/auth/v4/info` | Retrieve information about the current session (user ID, scopes). | _none_ | `200 OK` JSON payload with user details. | `401 Unauthorized` |
| **POST** | `/api/auth/v4` | Primary login endpoint (username/password). | ```json {"Username":"user@example.com","Password":"…"}``` | `200 OK` + session cookies. | `400 Bad Request`, `401 Unauthorized` |
| **GET** | `/api/core/v4/users` | Fetch the current user profile. | _none_ | `200 OK` JSON user object. | `401 Unauthorized` |
| **POST** | `/api/core/v4/auth` | Internal auth handshake (used by the Tauri navigation guard). | _none_ | `200 OK` if allowed. | `403 Forbidden` (blocked navigation) |
| **POST** | `/api/core/v4/auth/cookies` | Set authentication cookies (used in debugging). | _none_ | `200 OK` | `400 Bad Request` |
| **POST** | `/api/core/v4/auth/info` | Return auth session metadata. | _none_ | `200 OK` | `401 Unauthorized` |
| **POST** | `/api/core/v4/captcha` | Solve captcha challenge (used for login flow). | ```json {"CaptchaToken":"…"}``` | `200 OK` | `400 Bad Request`, `429 Too Many Requests` |
| **POST** | `/api/drive/v2/volumes/.../links` | Create a link (shortcut) for a volume. | ```json {"LinkName":"MyDrive"}``` | `200 OK` with link ID. | `400 Bad Request`, `401 Unauthorized` |
| **GET** | `/api/drive/v2/shares/photos` | List the **Photos** share metadata. | _none_ | `200 OK` JSON array of share objects. | `401 Unauthorized` |

> **Note** – The client does not expose a full OpenAPI spec. The table above is built from the source code (`src-tauri/src/auth.rs`, navigation code, and documentation in `docs/sync.md`). For any missing endpoint, consult the Proton backend documentation.

---

## Event‑Driven (WebSocket‑style) API
ProtonDrive Linux does not open a traditional WebSocket connection to the backend. Instead, it uses **Tauri events** that behave similarly to WebSocket messages. The two primary events are:

### 1. `live-sync://local-change`
**Direction:** Client → Front‑end (WebClients)

**Payload (JSON):**
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
- After a filesystem event is caught by `notify` (watcher) **or** by the periodic poller (`DEFAULT_SYNC_POLL_INTERVAL`).
- The event is filtered through a suppression cache to avoid ping‑pong loops.

**Consumer:** The JavaScript `ProtonDriveLinuxSyncBridge` in WebClients reads the payload and queues uploads via the Proton SDK.

### 2. Remote update handling (pseudo‑WebSocket)
**Direction:** Front‑end → Client

The front‑end calls the exposed Tauri command `handle_remote_update(change)` where `change` matches the `RemoteSyncChange` struct:
```rust
#[derive(Deserialize)]
pub struct RemoteSyncChange {
    pub relative_path: String,
    pub action: String,               // "create", "update", or "delete"
    pub content_base64: Option<String>,
}
```
The native side validates the path (rejects `..`, absolute paths, symlinks), writes or deletes the file under the sync root, and adds the path to the suppression cache so the subsequent local‑change event is ignored.

---

## Common Error Codes (Backend)
| Code | Meaning |
|------|---------|
| **400** | Bad request – missing/invalid parameters. |
| **401** | Unauthorized – missing or expired auth token. |
| **403** | Forbidden – operation not allowed (e.g., navigation to `/api/` is blocked). |
| **404** | Not found – endpoint or resource does not exist. |
| **429** | Too many requests – rate limiting. |
| **500** | Internal server error – backend failure. |

---

## How to Use This Reference
- **Developers** can copy the `curl` examples below into a terminal to test the endpoints against a live Proton backend (replace placeholders with real tokens).
- **Documentation writers** can expand each row with concrete request/response bodies once the official backend spec is available.
- **Test writers** can assert that the client emits `live-sync://local-change` with the exact payload shape defined above.

---

### Example `curl` for Login
```bash
curl -X POST https://mail.proton.me/api/auth/v4 \
  -H "Content-Type: application/json" \
  -d '{"Username":"user@example.com","Password":"myPassword"}'
```

### Example `curl` for Refresh
```bash
curl -X POST https://mail.proton.me/api/auth/v4/refresh \
  -H "Authorization: Bearer <refresh-token>"
```

---

*Generated by the Hermes Kanban worker for task **t_9c382198** – Docs review: API reference for v2 endpoints.*