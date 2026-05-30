# Proxy System

The proxy system is the most critical component — every API call from the Proton Drive SPA passes through it. Without it, the SPA cannot authenticate, list files, download, or sync anything.

## Why a proxy?

The Proton Drive SPA is designed to run in a browser at `drive.proton.me`. When we embed it in a WebView at `tauri://localhost/`, its API calls would either:

1. Hit the wrong origin (CORS blocks cross-origin `mail.proton.me` calls)
2. Hit `tauri://localhost/api/...` which doesn't exist

The proxy solves both by intercepting every fetch/XHR call and routing it through the Rust backend's `reqwest` client, which has no CORS restrictions.

## Two-layer interception

### Layer 1: `window.fetch` override

Location: init script, `main.rs` lines 1339–1485

```javascript
window.fetch = async function(input, init = {}) {
    let url = typeof input === 'string' ? input : (input.url || String(input));

    // Fix protocol-relative URLs (//assets/... → /assets/...)
    if (typeof url === 'string' && url.startsWith('//')) {
        url = url.substring(1);
    }

    // Non-API calls pass through to native fetch
    if (!url.includes('/api/')) {
        return originalFetch.call(window, fetchInput, init)
            .then(r => {
                // Log storage block requests
                if (isStorageBlockUrl(url)) { /* log */ }
                return r;
            });
    }

    // API calls go through proxy
    const proxiedRequest = await collectFetchRequest(input, init);
    // ... add captcha verification token if present ...
    const response = await invokeProxyRequest({
        request: { method: proxiedRequest.method, url, headers, body }
    });
    return new Response(response.body, { status: response.status, headers });
};
```

### Layer 2: `XMLHttpRequest` override

Location: init script, `main.rs` lines 1487–1537

```javascript
window.XMLHttpRequest = function() {
    const xhr = new OrigXHR();
    // ... capture method, url, headers on open/setRequestHeader ...
    xhr.send = function(body) {
        if (!url.includes('/api/')) return origSend.call(this, body);

        invokeProxyRequest({ request: { method, url, headers, body } })
            .then(response => {
                // Set xhr properties and fire events
                Object.defineProperty(xhr, 'status', { value: response.status });
                Object.defineProperty(xhr, 'responseText', { value: response.body });
                Object.defineProperty(xhr, 'readyState', { value: 4 });
                xhr.dispatchEvent(new Event('load'));
            });
    };
    return xhr;
};
```

## The serial invoke chain

**Critical design constraint**: WebKitGTK's Tauri IPC bridge can only handle **one in-flight `invoke()` call at a time** in certain configurations. If 5+ concurrent `invoke()` calls hit the bridge, Tauri falls back to `postMessage`, which has a known bug where JSON object responses never resolve — leaving the SPA frozen on the loading spinner forever.

The fix is a chained promise queue:

```javascript
let proxyInvokeChain = Promise.resolve();

function invokeProxyRequest(payload) {
    const next = proxyInvokeChain
        .catch(() => null)
        .then(() => window.__TAURI__.core.invoke('proxy_request', payload));
    proxyInvokeChain = next.catch(() => null);
    return next;
}
```

This serializes the JS→Rust crossing. The actual HTTPS requests still parallelize fine on the Rust side via `reqwest`'s connection pool — serialization only affects the IPC bridge, not the network.

## Rust proxy_request handler

Location: `main.rs` lines 386–510

### URL rewriting rules

| Input pattern | Rewrite |
|---|---|
| `https://localhost/api/...` | → `https://mail.proton.me/api/...` |
| `tauri://localhost/api/...` | → `https://mail.proton.me/api/...` |
| `/api/...` (relative) | → `https://mail.proton.me/api/...` |
| `https://mail.proton.me/...` | → unchanged (already absolute) |
| Anything else | → `https://mail.proton.me/<input>` |

```rust
let url = if request.url.starts_with("https://localhost/api/")
    || request.url.starts_with("http://localhost/api/")
{
    format!("{}{}", PROTON_API_BASE, &request.url[request.url.find("/api").unwrap()..])
} else if request.url.starts_with("https://") || request.url.starts_with("http://") {
    request.url.clone()
} else if request.url.starts_with("tauri://") {
    if let Some(idx) = request.url.find("/api") {
        format!("{}{}", PROTON_API_BASE, &request.url[idx..])
    } else {
        request.url.clone()
    }
} else if request.url.starts_with("/") {
    format!("{}{}", PROTON_API_BASE, request.url)
} else {
    format!("{}/{}", PROTON_API_BASE, request.url)
};
```

### Request construction

```rust
let mut req = state.client
    .request(method, &url)
    .timeout(PROXY_REQUEST_TIMEOUT);  // 45s

// Inject WebKit cookies
if let Some(cookie_header) = combined_cookie_header(&window, &state.cookie_jar, &target_url) {
    req = req.header(reqwest::header::COOKIE, cookie_header);
}

// Forward frontend headers (skip host and cookie)
for (key, value) in &request.headers {
    let k = key.to_lowercase();
    if k != "host" && k != "cookie" {
        req = req.header(key.as_str(), value.as_str());
    }
}

// Forward body
if let Some(ref body) = request.body {
    req = req.body(body.clone());
}
```

### Error handling

| Error | Status Code | Behavior |
|-------|-------------|----------|
| Timeout (45s) | 504 | Returns standard JSON error body |
| Connection failure | 502 | Returns standard JSON error body |
| Body read failure | 200 | Returns empty body |
| URL parse failure | — | Returns error string |
| Cookie read failure | — | Sends without cookies |

### Response processing

```rust
// Route Set-Cookie to WebKit's native jar
for (name, value) in resp.headers().iter() {
    if let Ok(v) = value.to_str() {
        if name.as_str().eq_ignore_ascii_case("set-cookie") {
            store_webview_cookie(&window, &target_url, v);
        } else {
            resp_headers.insert(name.to_string(), v.to_string());
        }
    }
}
```

This means **WebKit manages all cookies** — authentication, CSRF tokens, session data. The Rust `reqwest` cookie jar is separate and used only for edge cases.

## Request body serialization

The init script handles multiple body types:

```javascript
const requestBodyToString = async (body) => {
    if (body == null) return null;
    if (typeof body === 'string') return body;
    if (body instanceof URLSearchParams) return body.toString();
    if (body instanceof FormData) return new URLSearchParams(body).toString();
    if (body instanceof Blob) return await body.text();
    if (body instanceof ArrayBuffer) return new TextDecoder().decode(body);
    if (ArrayBuffer.isView(body)) {
        return new TextDecoder().decode(body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength));
    }
    if (body instanceof ReadableStream) {
        throw new Error('ReadableStream request bodies are not supported by the Tauri API proxy');
    }
    return JSON.stringify(body);
};
```

**Notable limitation**: `ReadableStream` bodies are explicitly rejected. The Proton SPA occasionally uses streaming uploads (e.g., chunked file uploads). When this happens, the proxy throws — this is a known design constraint, not a bug. Streaming uploads would require a completely different transport mechanism that Tauri's IPC bridge doesn't support.

## Storage block monitoring

Proton Drive stores files as encrypted "blocks." The SPA fetches them from `/storage/blocks/...`. These requests bypass the proxy (they don't contain `/api/`) but are logged for debugging:

```javascript
const isStorageBlockUrl = (url) => {
    try {
        const parsed = new URL(url, window.location.href);
        return parsed.pathname.includes('/storage/blocks');
    } catch {
        return String(url || '').includes('/storage/blocks');
    }
};
```

Storage block requests are logged with method, URL, body length, response status, and content-length. This is how you diagnose "file won't download" issues — if storage block requests consistently fail with 4xx/5xx, the session is invalid.

## CAPTCHA-in-proxy detection

The fetch override detects CAPTCHA challenges during proxy requests:

```javascript
if (response.status === 422 && response.body) {
    const data = JSON.parse(response.body);
    if (data.Code === 9001 && data.Details?.HumanVerificationToken) {
        // Save current credentials, navigate to verify.proton.me
    }
}
```

Proton returns HTTP 422 with error code 9001 when a human verification (CAPTCHA) is required. The proxy:
1. Captures the current login form values (email + password)
2. Stores them via `store_login_credentials` Tauri command
3. Navigates the WebView to `verify.proton.me` as a top-level document

After verification completes, the verify page posts `HUMAN_VERIFICATION_SUCCESS` via `postMessage`. The init script captures this, returns to the account page, and the stored credentials are auto-filled into the login form.

## Performance & logging

### Hot path optimization

The proxy explicitly avoids logging fetch details in the hot path:

```javascript
// Note: FETCH-level logging removed from hot path.
// Each js_log invoke adds IPC pressure that can break the WebKitGTK
// IPC bridge under concurrent load (5 SPA fetches + 5 FETCH logs
// + 5 PROXY_REQ logs = 15 concurrent invokes, vs ~5 on main).
```

Each `window.__TAURI__.core.invoke('js_log', ...)` is a full IPC round-trip. Under load, logging each fetch doubles the IPC pressure and can break the bridge.

### Rust-side logging

The Rust proxy logs each request with a unique ID:

```
[Proxy][0] POST https://mail.proton.me/api/core/v4/auth start
[Proxy][0] 200 <- https://mail.proton.me/api/core/v4/auth elapsed_ms=234 body=1024
```

### Protocol-relative URL handling

A subtle but important fix: Proton's SPA occasionally emits protocol-relative URLs like `//assets/...`. In a browser, these resolve to `https://assets/...`. In a `tauri://` WebView, they resolve to `tauri://assets/...`, which is invalid. The proxy rewrites `//` → `/`.

## Timeout & retry behavior

| Parameter | Value | Applies to |
|-----------|-------|------------|
| `PROXY_CONNECT_TIMEOUT` | 15s | TCP connection to Proton API |
| `PROXY_REQUEST_TIMEOUT` | 45s | Entire request-response cycle |

There is **no automatic retry** in the proxy layer. If a request fails with 502/504, the SPA's own retry logic (if any) handles it. The proxy returns the error and moves on.

## Troubleshooting

### 502 Bad Gateway from Proton API

**Symptoms:** Console shows `PROXY_RESP: 502` for API requests. Drive UI shows "Error loading" or blank sections.

**Causes:**
- Proton's API is temporarily down or rate-limiting the request
- The request body is malformed (Proton returns 502 for some validation errors)
- DNS resolution failed for `drive-api.proton.me` or `api.proton.me`

**Fix:**
1. Check if Proton services are up: visit `https://status.proton.me`
2. Verify DNS: `dig drive-api.proton.me` — should resolve
3. Check the request body in console logs (look for `PROXY_REQ` before the error)
4. Wait and retry — Proton rate limits reset after ~60 seconds

### Requests Hanging (Timeout)

**Symptoms:** Console shows `PROXY_REQ` but no matching `PROXY_RESP`. UI frozen.

**Causes:**
- Network connectivity issue (firewall blocking outbound HTTPS)
- Proton API is slow (rare — timeout is 45s)
- The reqwest client's connection pool is exhausted

**Fix:**
1. Check network: `curl -m 10 https://api.proton.me` — should return quickly
2. Verify firewall allows outbound HTTPS on port 443
3. Restart the app to reset the connection pool
4. Check for DNS issues: the app uses system DNS, try `resolvectl` or `nslookup`

### CORS Errors in Console

**Symptoms:** WebView console shows `Access-Control-Allow-Origin` errors for API calls.

**Causes:**
- A fetch/XHR request bypassed the proxy and hit the API directly
- The proxy initialization script didn't run (the `init.js` injection failed)
- The URL didn't match the proxy's interception rules

**Fix:**
1. Check the request URL — is it going through `tauri://localhost` (proxied) or directly to `https://api.proton.me` (blocked)?
2. Verify the init script is injected: check DevTools Sources tab for an injected `<script>` in the `<head>`
3. If using a custom build, verify the init script is included in `frontendDist`

## See Also

- **[WebView Integration](../webview/webview-integration.md)** — How the proxy is injected and configured in the WebView
- **[Proton Navigation](proton-navigation.md)** — URL rewriting decisions that route requests through vs. around the proxy
- **[Auth Module](../auth/auth-module.md)** — Cookie/header injection at the proxy boundary
- **[Architecture](architecture.md)** — How the proxy fits into the AppState
