---
title: "URL Logging & WebView Storage"
created: 2026-05-28
updated: 2026-05-28
type: utility
tags: [storage, configuration, webview]
sources:
  - src-tauri/src/url_log.rs
  - src-tauri/src/webview_storage.rs
---

# URL Logging & WebView Storage

Two small utility modules that handle logging hygiene and persistent storage.

---

## `url_log.rs` — URL Sanitization for Log Output

**Path:** `src-tauri/src/url_log.rs` (8 lines)

**Purpose:** Strips query parameters and URL fragments before logging any URL to
the console. This prevents sensitive data — access tokens, session IDs, CSRF
tokens, and other query-string secrets — from appearing in terminal output.

### Public API

```rust
/// Returns a URL without query parameters or fragments for log output.
pub fn sanitize_url_for_log(url: &str) -> String
```

### Behavior

| Input | Output |
|---|---|
| `https://account.proton.me/login?token=abc123` | `https://account.proton.me/login` |
| `https://drive.proton.me/my-files#section` | `https://drive.proton.me/my-files` |
| `https://api.proton.me/core/v4/users?Page=0&PageSize=10` | `https://api.proton.me/core/v4/users` |
| Unparseable string | `"<unparsed-url>"` |

### Where It's Used

Called from `main.rs` in navigation and proxy logging:

```rust
use url_log::sanitize_url_for_log;

// Navigation events
println!("[Navigate] URL: {}", sanitize_url_for_log(url));

// Proxy requests
println!("[Proxy] PROXY_REQ #{}: {} {}",
    request_id, method, sanitize_url_for_log(target_url));
```

### Why It Matters

Proton's SSO flow passes `token`, `session`, and `redirect` parameters in query
strings. Without sanitization, each navigation log would leak authentication
tokens to the terminal/`journalctl`. The sanitizer ensures logs are safe to
share in bug reports and debug sessions.

---

## `webview_storage.rs` — Persistent WebView Data Directory

**Path:** `src-tauri/src/webview_storage.rs` (11 lines)

**Purpose:** Returns and creates the directory where WebKit stores persistent
data — IndexedDB, localStorage, cookies, and service worker registrations.
Without this, Proton Drive's session data would not survive app restarts.

### Public API

```rust
/// Returns the persistent WebView storage directory under the app data folder.
pub fn persistent_webview_data_dir(app_data_dir: PathBuf) -> PathBuf

/// Ensures the persistent WebView storage directory exists.
pub fn ensure_webview_data_dir(dir: &Path) -> std::io::Result<()>
```

### Path Resolution

```text
app_data_dir                     (e.g. ~/.local/share/com.proton.drive)
└── webview/                     ← persistent_webview_data_dir() return value
    ├── localStorage/            ← Proton Drive session state
    ├── IndexedDB/               ← Crypto keys and file metadata cache
    ├── Cookies                  ← AUTH, REFRESH, and session cookies
    └── Service Workers/         ← Background sync (unused)
```

### Where It's Called

From `main.rs` during Tauri app setup:

```rust
let webview_data_dir = persistent_webview_data_dir(
    app.path().app_data_dir()?
);
ensure_webview_data_dir(&webview_data_dir).map_err(|e| {
    format!("Failed to create WebView data directory: {e}")
})?;
```

### Why It Matters

- **Session persistence** — Without this directory, every app restart is a fresh login. WebKit falls back to in-memory storage if the data directory doesn't exist or isn't writable.
- **Sandbox prerequisite** — WebKit's sandbox must be disabled (`WEBKIT_FORCE_SANDBOX=0`) for persistent storage writes to work. See [Configuration Reference](configuration-reference.md).
- **Permissions** — The directory must be owned by the user running the app. If the app was run as `sudo` once, subsequent normal-user runs may fail to write.

### Troubleshooting

**Symptoms:** Login state resets every restart. Settings don't persist.

**Check:**
```bash
ls -la ~/.local/share/com.proton.drive/webview/
# Should contain: Cookies, IndexedDB, localStorage
```

If the directory is empty or missing, the app likely failed to create it. Check
the app's console output for `[Storage] Using persistent WebView data directory`
— if this message doesn't appear, the directory wasn't set up.

---

## See Also

- **[Configuration Reference](configuration-reference.md)** — All env vars, constants, and file paths
- **[WebView Integration](webview-integration.md)** — Full WebView subsystem, cookie handling, IPC
- **[Auth Module](auth-module.md)** — Session lifecycle, cookie persistence
- **[Architecture](ARCHITECTURE.md)** — How these modules fit into the AppState
