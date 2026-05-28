# Blob Download System

Proton Drive serves files through encrypted "block" downloads. The SPA decrypts blocks in JavaScript and constructs a Blob, then triggers a download. On Linux, we intercept this entire chain and route it to the native filesystem.

## The problem

In a browser, downloading a Blob works natively:
1. Create blob → `URL.createObjectURL(blob)`
2. Create `<a>` with `download` attribute and `href=blob:...`
3. Click the anchor → browser triggers native download

In a Tauri WebView, this doesn't work because `blob:` URLs aren't a real protocol. The WebView has no built-in download handler for them.

## The solution: multi-point interception

The init script intercepts **every possible download path**:

### 1. Blob URL tracking

```javascript
const origCreateObjectURL = URL.createObjectURL;

URL.createObjectURL = function(blob) {
    const url = origCreateObjectURL.call(URL, blob);
    if (!window.__blobUrls) window.__blobUrls = new Map();
    window.__blobUrls.set(url, blob);   // Track blob by URL
    return url;
};
```

Every Blob created via `URL.createObjectURL()` is stored in `window.__blobUrls` keyed by its `blob:` URL.

### 2. Filename capture (three methods)

Proton's SPA sets the download filename in several ways. We intercept all of them:

**Method A: `setAttribute('download', ...)`**
```javascript
const origSetAttribute = Element.prototype.setAttribute;
Element.prototype.setAttribute = function(name, value) {
    if (name === 'download' && this.tagName === 'A') {
        pendingDownloadName = value;
        window.__pendingDownloadName = value;
    }
    return origSetAttribute.call(this, name, value);
};
```

**Method B: Property assignment on HTMLAnchorElement**
```javascript
const anchorProto = HTMLAnchorElement.prototype;
const downloadDesc = Object.getOwnPropertyDescriptor(anchorProto, 'download');
if (downloadDesc) {
    Object.defineProperty(anchorProto, 'download', {
        get: downloadDesc.get,
        set: function(value) {
            pendingDownloadName = value;
            window.__pendingDownloadName = value;
            return downloadDesc.set.call(this, value);
        },
        configurable: true
    });
}
```

**Method C: MutationObserver on created anchors**
```javascript
const origCreateElement = document.createElement;
document.createElement = function(tag, options) {
    const el = origCreateElement.call(document, tag, options);
    if (tag.toLowerCase() === 'a') {
        const observer = new MutationObserver((mutations) => {
            for (const m of mutations) {
                if (m.attributeName === 'download') {
                    const val = el.getAttribute('download');
                    if (val) pendingDownloadName = val;
                }
            }
        });
        observer.observe(el, { attributes: true, attributeFilter: ['download'] });
    }
    return el;
};
```

### 3. Download trigger interception

**Click handler (capture phase):**
```javascript
document.addEventListener('click', async (e) => {
    const anchor = e.target.closest('a');
    if (!anchor) return;

    const href = anchor.href;
    if (!href || !href.startsWith('blob:')) return;

    e.preventDefault();
    e.stopPropagation();
    await handleBlobDownload(href, anchor.download || pendingDownloadName || 'download');
}, true);  // capture phase — fires before SPA handlers
```

**`window.open` override:**
```javascript
const origWindowOpen = window.open;
window.open = function(url, ...args) {
    if (url && url.startsWith('blob:')) {
        handleBlobDownload(url, pendingDownloadName || 'download');
        return null;
    }
    return origWindowOpen.call(window, url, ...args);
};
```

**Navigation interception (Rust side):**
```rust
.on_navigation(move |url| {
    if url.scheme() == "blob" {
        // Inject JS to handle the blob download
        window.eval(format!(r#"
            (async function() {{
                const blob = window.__blobUrls?.get("{}");
                if (blob) {{
                    const bytes = Array.from(new Uint8Array(await blob.arrayBuffer()));
                    await window.__TAURI__.core.invoke('save_download', {{
                        filename: window.__pendingDownloadName || 'download',
                        data: bytes
                    }});
                }}
            }})();
        "#, blob_url));
        return false; // Block blob navigation
    }
})
```

### 4. The actual save

```javascript
async function handleBlobDownload(blobUrl, filename) {
    const blob = window.__blobUrls?.get(blobUrl);
    if (!blob) {
        console.error('[Download] Blob not found for:', blobUrl);
        return;
    }
    try {
        console.log('[Download] Saving:', filename, 'size:', blob.size);
        const buffer = await blob.arrayBuffer();
        const bytes = Array.from(new Uint8Array(buffer));
        const path = await window.__TAURI__.core.invoke('save_download', {
            filename: filename,
            data: bytes
        });
        console.log('[Download] Saved to:', path);
    } catch (err) {
        console.error('[Download] Failed:', err);
    }
}
```

### 5. Rust save_download command

```rust
#[tauri::command]
async fn save_download(filename: String, data: Vec<u8>) -> Result<String, String> {
    let downloads_dir = dirs::download_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join("Downloads")))
        .ok_or("Unable to access download location")?;

    // Ensure downloads dir exists
    std::fs::create_dir_all(&downloads_dir).map_err(|e| {
        eprintln!("[Download] Failed to create downloads dir {:?}: {e}", downloads_dir);
        "Unable to save download".to_string()
    })?;

    let file_path = downloads_dir.join(&filename);
    println!("[Download] Saving file to Downloads folder");

    std::fs::write(&file_path, &data).map_err(|e| {
        eprintln!("[Download] Failed to write download {:?}: {e}", file_path);
        "Unable to save download".to_string()
    })?;

    Ok(file_path.to_string_lossy().to_string())
}
```

## Native WebView downloads (non-blob)

For regular HTTP downloads (not proton block downloads), the `on_download` handler routes to `~/Downloads`:

```rust
.on_download(|_webview, event| {
    match event {
        DownloadEvent::Requested { url, destination } => {
            if let Some(home) = dirs::home_dir() {
                let downloads_dir = home.join("Downloads");
                if let Some(filename) = url.as_str().split('/').last() {
                    let clean_name = filename.split('?').next().unwrap_or(filename);
                    *destination = downloads_dir.join(clean_name);
                }
            }
            true  // Allow download
        }
        DownloadEvent::Finished { success, .. } => {
            println!("[Download] Finished, success: {}", success);
            true
        }
        _ => true
    }
})
```

## Download flow summary

```
Proton SPA decrypts block
    → creates Blob
    → URL.createObjectURL(blob)  [intercepted: blob stored in __blobUrls]
    → creates <a download="filename.pdf">  [intercepted: filename captured]
    → clicks the anchor or opens window  [intercepted: click handler / window.open]
    → handleBlobDownload(blobUrl, filename)
        → blob.arrayBuffer()
        → Array.from(new Uint8Array(buffer))
        → invoke('save_download', { filename, data })
            → Rust: std::fs::write(~/{Downloads}/{filename}, data)
            → returns absolute path
```

## Known constraints

- **Maximum file size**: Limited by WebView memory — the entire decrypted Blob is held in JS memory as an ArrayBuffer before sending to Rust. Very large files (>500MB) may cause memory pressure.
- **No streaming**: The entire file must be decrypted and held in memory before the download starts. There's no chunked/streaming path through the Tauri IPC bridge.
- **Concurrent downloads**: Each download holds a full file in JS memory. Multiple concurrent downloads compound memory usage.

## See Also

- **[WebView Integration](webview-integration.md)** — How the download pipeline connects to the WebView bridge
- **[Auth Module](auth-module.md)** — The blob download intercept and `save_download` command
- **[Architecture](ARCHITECTURE.md)** — How downloads fit into the AppState
