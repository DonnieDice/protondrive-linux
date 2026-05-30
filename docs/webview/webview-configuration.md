# WebView Configuration & Init Script

The WebView initialization is a ~1,500-line JavaScript string embedded in `main.rs` and injected via `WebviewWindowBuilder::initialization_script()`. It runs **before any SPA code** and installs all the native integration hooks.

## Environment variables

Set before the Tauri app starts:

```rust
std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
std::env::set_var("WEBKIT_FORCE_SANDBOX", "0");
std::env::set_var("GDK_GL", "disable");
std::env::set_var("GSK_RENDERER", "cairo");
```

| Variable | Effect |
|----------|--------|
| `WEBKIT_DISABLE_DMABUF_RENDERER=1` | Disables DMA-BUF GPU buffer sharing — causes rendering artifacts on many Linux GPU drivers |
| `WEBKIT_DISABLE_COMPOSITING_MODE=1` | Disables hardware compositing — prevents GPU driver crashes with WebKitGTK |
| `WEBKIT_FORCE_SANDBOX=0` | Disables WebKit's process sandbox — required for Tauri's IPC bridge to work |
| `GDK_GL=disable` | Disables GTK's OpenGL integration — forces software rendering |
| `GSK_RENDERER=cairo` | Forces the Cairo 2D renderer — most compatible across distros |

**Why these are needed**: Different Linux distros ship different WebKitGTK builds with varying GPU support. Without these variables, the WebView often renders as a black/white window, crashes on GPU driver initialization, or freezes during page transitions. Cairo rendering is slower but works everywhere.

## Window configuration

```rust
WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
    .title("Proton Drive")
    .inner_size(1200.0, 800.0)
    .min_inner_size(800.0, 600.0)
    .data_directory(webview_data_dir)       // Persistent WebKit data
    .initialization_script(init_script)      // The ~1,500 line JS
    .devtools(true)                          // Right-click → Inspect Element
    .on_download(...)                        // Route downloads to ~/Downloads
    .on_navigation(...)                      // SSO routing
    .build()?;
```

### Persistent WebView data directory

```rust
fn persistent_webview_data_dir(app_data_dir: PathBuf) -> PathBuf {
    app_data_dir.join("webview")
}

fn ensure_webview_data_dir(dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)
}
```

The WebView data directory stores cookies, localStorage, IndexedDB, and cache. Without persistence, every app restart would require re-authentication.

## The initialization script (full breakdown)

The init script is constructed as a Rust string and injected into the WebView. Here's every subsystem:

### 1. Worker polyfill (distro-dependent)

```javascript
// appimage / aur: Native Workers
console.log('[INIT] AppImage/AUR build - using native Workers');

// rpm / deb / flatpak / snap: Override Workers
window.Worker = undefined;
window.SharedWorker = undefined;
console.log('[INIT] Workers set to undefined - Proton will load crypto API in main thread');
```

Proton's SPA uses Web Workers for cryptographic operations (encryption/decryption). On system WebKitGTK builds, Workers throw "operation is insecure" errors. By setting `Worker` and `SharedWorker` to `undefined` **before any Proton code loads**, the SPA detects the absence and falls back to main-thread crypto via `packages/shared/lib/helpers/setupCryptoWorker.ts`.

For unknown distros, there's an even more aggressive override:

```javascript
// Unknown distro fallback
const OrigWorker = window.Worker;
window.Worker = function Worker(url) {
    throw new Error('Worker not supported');
};

window.SharedWorker = function SharedWorker(url) {
    return {
        port: {
            postMessage: function() {},
            start: function() {},
            close: function() {},
            addEventListener: function() {},
            removeEventListener: function() {},
            onmessage: null,
            onmessageerror: null
        },
        onerror: null
    };
};

// Freeze the overrides to prevent SPA from reinstating
Object.defineProperty(window, 'Worker', {
    value: window.Worker, writable: false, configurable: false
});
Object.defineProperty(window, 'SharedWorker', {
    value: window.SharedWorker, writable: false, configurable: false
});
```

### 2. SSO route restoration

```javascript
try {
    if (window.location.protocol === 'tauri:'
        && window.location.hostname === 'localhost'
        && window.location.pathname === '/') {

        const sessionKey = Object.keys(localStorage).find(key => /^ps-\d+$/.test(key));
        const localId = sessionKey && sessionKey.slice(3);
        if (localId) {
            history.replaceState({}, '', `/u/${localId}/`);
        }
    }
} catch (e) {
    console.warn('[SSO] Failed to restore Drive user route:', e);
}
```

### 3. Blob download interception

(Covered in detail in [Blob Downloads](../reference/blob-downloads.md))

### 4. CAPTCHA handling

(Covered in detail in [SSO & Authentication](../auth/sso-authentication.md))

### 5. Console-to-Rust bridge

```javascript
const sendToRust = (level, args) => {
    try {
        const msg = '[' + level + '] ' + Array.from(args).map(a => {
            try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
            catch { return String(a); }
        }).join(' ');
        window.__TAURI__?.core?.invoke('js_log', { msg });
    } catch {}
};

console.log = function(...args) { sendToRust('LOG', args); origLog.apply(console, args); };
console.error = function(...args) { sendToRust('ERR', args); origError.apply(console, args); };
console.warn = function(...args) { sendToRust('WARN', args); origWarn.apply(console, args); };
```

The Rust `js_log` handler simply prints:

```rust
#[tauri::command]
fn js_log(msg: String) {
    println!("[JS] {}", msg);
}
```

### 6. Error boundary

```javascript
window.onerror = (msg, src, line, col, err) => {
    sendToRust('UNCAUGHT', [msg, 'at', src + ':' + line + ':' + col, err?.stack || '']);
};

window.onunhandledrejection = (e) => {
    const reason = e.reason;
    let msg = '';
    if (reason instanceof Error) {
        msg = reason.message + ' | ' + (reason.stack || '');
    } else {
        try { msg = JSON.stringify(reason); } catch { msg = String(reason); }
    }
    sendToRust('UNHANDLED', [msg]);
};
```

### 7. Startup diagnostics

(Covered in [Architecture](../architecture/architecture.md#startup-diagnostics))

### 8. Fetch/XHR proxy (the hot path)

(Covered in [Proxy System](../architecture/proxy-system.md))

### 9. Script load error tracking

```javascript
window.addEventListener('error', async (e) => {
    if (e.target && e.target.tagName === 'SCRIPT') {
        console.error('[SCRIPT ERROR]', e.target.src);
        try {
            const response = await fetch(e.target.src);
            console.error('[SCRIPT ERROR] HTTP Status:', response.status);
            const text = await response.text();
            console.error('[SCRIPT ERROR] Response preview:', text.substring(0, 200));
        } catch (err) {
            console.error('[SCRIPT ERROR] Fetch failed:', err.message);
        }
    }
}, true);
```

This catches SCRIPT load failures (common when WebKitGTK can't load a chunk) and logs the HTTP status and response preview.

## Navigation handler

The `on_navigation` handler in Rust manages all URL routing:

```rust
.on_navigation(move |url| {
    // 1. Blob URLs → trigger download, block navigation
    // 2. /login paths → rewrite to /account/?product=drive
    // 3. account.proton.me → local /account/...
    // 4. drive.proton.me → local root
    // 5. Login completion → about:blank → reload Drive
    // 6. CAPTCHA URLs → allow with state tracking
    // 7. hCaptcha domains → allow
    // 8. Unsupported Proton apps → redirect to Drive
    // 9. /api/ navigation → block (should use fetch)
    // 10. Otherwise: allow tauri://, about:, localhost
})
```

## Tauri plugin configuration

Three plugins are registered:

```rust
.plugin(tauri_plugin_shell::init())        // Sidecar/mobile pattern (unused, but available)
.plugin(tauri_plugin_dialog::init())       // Native file dialogs (unused, but available)
.plugin(tauri_plugin_notification::init()) // Desktop notifications (unused, but available)
```

These are registered but not actively used by the current app. They're available for future features.

## DevTools

```rust
.devtools(true)
```

This enables WebKit's Web Inspector via right-click → Inspect Element. Critical for debugging SPA rendering issues, network requests, and localStorage state.

## App state

```rust
struct AppState {
    client: Client,              // reqwest HTTP client
    cookie_jar: Arc<Jar>,        // reqwest cookie jar (secondary to WebKit's)
    sync_manager: LiveSyncManager, // Filesystem sync
}
```

Managed via Tauri's state system:

```rust
.manage(Arc::new(AppState { ... }))
```

All Tauri commands access state via `State<'_, Arc<AppState>>`.
