#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::collections::HashMap;
use std::sync::Arc;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};

const PROTON_API_BASE: &str = "https://mail.proton.me";

// Shared HTTP client with cookie jar
struct AppState {
    client: Client,
}

#[derive(Debug, Deserialize)]
struct ProxyRequest {
    method: String,
    url: String,
    headers: HashMap<String, String>,
    body: Option<String>,
}

#[derive(Debug, Serialize)]
struct ProxyResponse {
    status: u16,
    headers: HashMap<String, String>,
    body: String,
}

#[tauri::command]
fn js_log(msg: String) {
    println!("[JS] {}", msg);
}

// Store the return URL when navigating to captcha
static CAPTCHA_RETURN_URL: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);

// Track if we're currently on a captcha page
static ON_CAPTCHA_PAGE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

// Store verification token in memory only (zero trust - cleared after use)
static PENDING_VERIFICATION: std::sync::Mutex<Option<(String, String)>> = std::sync::Mutex::new(None);

// Store login credentials during captcha flow (zero trust - cleared after use)
static PENDING_CREDENTIALS: std::sync::Mutex<Option<(String, String)>> = std::sync::Mutex::new(None);

#[tauri::command]
fn store_verification_token(token: String, token_type: String) {
    println!("[CAPTCHA] Storing verification token in memory");
    *PENDING_VERIFICATION.lock().unwrap() = Some((token, token_type));
}

#[tauri::command]
fn get_and_clear_verification_token() -> Option<(String, String)> {
    let result = PENDING_VERIFICATION.lock().unwrap().take();
    if result.is_some() {
        println!("[CAPTCHA] Retrieved and cleared verification token");
    }
    result
}

#[tauri::command]
fn store_login_credentials(username: String, password: String) {
    println!("[CAPTCHA] Storing login credentials temporarily");
    *PENDING_CREDENTIALS.lock().unwrap() = Some((username, password));
}

#[tauri::command]
fn get_and_clear_login_credentials() -> Option<(String, String)> {
    let result = PENDING_CREDENTIALS.lock().unwrap().take();
    if result.is_some() {
        println!("[CAPTCHA] Retrieved and cleared login credentials");
    }
    result
}

#[tauri::command]
async fn navigate_to_captcha(app: tauri::AppHandle, captcha_url: String, return_url: String) -> Result<(), String> {
    println!("[CAPTCHA] Navigating main window to: {}", captcha_url);
    println!("[CAPTCHA] Will return to: {}", return_url);

    // Store return URL
    *CAPTCHA_RETURN_URL.lock().unwrap() = Some(return_url);

    // Navigate main window to captcha (local or external)
    if let Some(window) = app.get_webview_window("main") {
        let url: tauri::Url = captcha_url.parse().map_err(|e| format!("Invalid URL: {}", e))?;
        window.navigate(url).map_err(|e| format!("Navigation failed: {}", e))?;
    }

    Ok(())
}

#[tauri::command]
fn get_captcha_return_url() -> Option<String> {
    CAPTCHA_RETURN_URL.lock().unwrap().take()
}

#[tauri::command]
async fn save_download(filename: String, data: Vec<u8>) -> Result<String, String> {
    let downloads_dir = dirs::download_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join("Downloads")))
        .ok_or("Could not find Downloads directory")?;

    // Ensure downloads dir exists
    std::fs::create_dir_all(&downloads_dir)
        .map_err(|e| format!("Failed to create Downloads dir: {}", e))?;

    let file_path = downloads_dir.join(&filename);
    println!("[Download] Saving to: {:?}", file_path);

    std::fs::write(&file_path, &data)
        .map_err(|e| format!("Failed to write file: {}", e))?;

    Ok(file_path.to_string_lossy().to_string())
}

#[tauri::command]
async fn proxy_request(
    state: tauri::State<'_, Arc<AppState>>,
    request: ProxyRequest,
) -> Result<ProxyResponse, String> {
    // Build the target URL - extract path from various URL formats
    let url = if request.url.starts_with("https://localhost/api/") || request.url.starts_with("http://localhost/api/") {
        // Rewrite localhost API calls to Proton
        format!("{}{}", PROTON_API_BASE, &request.url[request.url.find("/api").unwrap()..])
    } else if request.url.starts_with("https://") || request.url.starts_with("http://") {
        request.url.clone()
    } else if request.url.starts_with("tauri://") {
        // Extract /api/... path from tauri:// URLs
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

    let method = reqwest::Method::from_bytes(request.method.to_uppercase().as_bytes())
        .unwrap_or(reqwest::Method::GET);

    println!("[Proxy] {} {}", method, url);

    let mut req = state.client.request(method, &url);

    // Forward headers from frontend (skip cookie - client handles it)
    for (key, value) in &request.headers {
        let k = key.to_lowercase();
        // Skip cookie header - reqwest cookie jar handles cookies automatically
        if k != "host" && k != "cookie" {
            req = req.header(key.as_str(), value.as_str());
        }
    }

    if let Some(ref body) = request.body {
        req = req.body(body.clone());
    }

    let resp = req.send().await.map_err(|e| format!("Request failed: {}", e))?;
    let status = resp.status().as_u16();

    // Forward response headers including set-cookie (needed for WebView session)
    let mut resp_headers = HashMap::new();
    let mut set_cookies: Vec<String> = Vec::new();
    for (name, value) in resp.headers().iter() {
        if let Ok(v) = value.to_str() {
            if name.as_str().eq_ignore_ascii_case("set-cookie") {
                set_cookies.push(v.to_string());
            } else {
                resp_headers.insert(name.to_string(), v.to_string());
            }
        }
    }
    // Join multiple set-cookie headers with a delimiter JS can split on
    if !set_cookies.is_empty() {
        resp_headers.insert("x-set-cookie".to_string(), set_cookies.join("|||"));
    }

    let body = resp.text().await.unwrap_or_default();

    println!("[Proxy] {} <- {}", status, url);
    if body.len() < 500 {
        println!("[Proxy] Body: {}", body);
    }

    Ok(ProxyResponse { status, headers: resp_headers, body })
}

fn main() {
    // Fix WebKitGTK EGL/GPU issues on various Linux configurations
    std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
    std::env::set_var("WEBKIT_FORCE_SANDBOX", "0");
    std::env::set_var("GDK_GL", "disable");
    std::env::set_var("GSK_RENDERER", "cairo");

    // Create shared client with cookie jar
    let state = Arc::new(AppState {
        client: Client::builder()
            .cookie_store(true)  // Enable cookie jar
            .build()
            .expect("Failed to create HTTP client"),
    });

    tauri::Builder::default()
        .manage(state)
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            let init_script = r#"
(function() {
    // Intercept Blob downloads and save to ~/Downloads
    const origCreateObjectURL = URL.createObjectURL;
    let pendingDownloadName = null;

    URL.createObjectURL = function(blob) {
        const url = origCreateObjectURL.call(URL, blob);
        if (!window.__blobUrls) window.__blobUrls = new Map();
        window.__blobUrls.set(url, blob);
        console.log('[Blob] Created:', url, 'size:', blob.size);
        return url;
    };

    // Intercept window.open for blob URLs
    const origWindowOpen = window.open;
    window.open = function(url, ...args) {
        if (url && url.startsWith('blob:')) {
            console.log('[Download] Intercepted window.open blob:', url);
            handleBlobDownload(url, pendingDownloadName || 'download');
            return null;
        }
        return origWindowOpen.call(window, url, ...args);
    };

    // Intercept location assignment for blob URLs
    const locationDescriptor = Object.getOwnPropertyDescriptor(window, 'location');
    // Can't override location directly, but we can intercept anchor navigation

    // Intercept anchor clicks with download attribute OR href to blob
    document.addEventListener('click', async (e) => {
        const anchor = e.target.closest('a');
        if (!anchor) return;

        const href = anchor.href;
        if (!href || !href.startsWith('blob:')) return;

        e.preventDefault();
        e.stopPropagation();

        const filename = anchor.download || pendingDownloadName || 'download';
        console.log('[Download] Intercepted anchor click:', filename);
        await handleBlobDownload(href, filename);
    }, true);

    // Watch for download filename from Proton's download logic
    const origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) {
        if (name === 'download' && this.tagName === 'A') {
            pendingDownloadName = value;
            window.__pendingDownloadName = value;
            console.log('[Download] setAttribute filename:', value);
        }
        return origSetAttribute.call(this, name, value);
    };

    // Also intercept direct property assignment
    const anchorProto = HTMLAnchorElement.prototype;
    const downloadDesc = Object.getOwnPropertyDescriptor(anchorProto, 'download');
    if (downloadDesc) {
        Object.defineProperty(anchorProto, 'download', {
            get: downloadDesc.get,
            set: function(value) {
                pendingDownloadName = value;
                window.__pendingDownloadName = value;
                console.log('[Download] Property filename:', value);
                return downloadDesc.set.call(this, value);
            },
            configurable: true
        });
    }

    // Also watch for anchor creation with download attribute
    const origCreateElement = document.createElement;
    document.createElement = function(tag, options) {
        const el = origCreateElement.call(document, tag, options);
        if (tag.toLowerCase() === 'a') {
            // Watch this anchor for download attribute changes
            const observer = new MutationObserver((mutations) => {
                for (const m of mutations) {
                    if (m.attributeName === 'download') {
                        const val = el.getAttribute('download');
                        if (val) {
                            pendingDownloadName = val;
                            window.__pendingDownloadName = val;
                            console.log('[Download] Observed filename:', val);
                        }
                    }
                }
            });
            observer.observe(el, { attributes: true, attributeFilter: ['download'] });
        }
        return el;
    };

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

    // Track if we have a pending captcha - to avoid opening multiple windows
    let captchaPending = false;
    let lastCaptchaToken = null;
    let pendingAuthBody = null;  // Store auth request body for retry after captcha

    // On page load, check if we have stored credentials to restore
    // ONLY on tauri://localhost pages (not external captcha pages)
    (async function() {
        if (!window.location.href.startsWith('tauri://')) {
            return;  // Don't run on external pages like verify.proton.me
        }
        try {
            const creds = await window.__TAURI__?.core?.invoke('get_and_clear_login_credentials');
            if (creds && creds[0] && creds[1]) {
                console.log('[CAPTCHA] Restoring saved credentials');

                // Helper to set React input value properly
                const setNativeValue = (element, value) => {
                    const valueSetter = Object.getOwnPropertyDescriptor(element, 'value')?.set;
                    const prototype = Object.getPrototypeOf(element);
                    const prototypeValueSetter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;

                    if (valueSetter && valueSetter !== prototypeValueSetter) {
                        prototypeValueSetter.call(element, value);
                    } else if (valueSetter) {
                        valueSetter.call(element, value);
                    } else {
                        element.value = value;
                    }

                    // Dispatch events React listens to
                    element.dispatchEvent(new Event('input', { bubbles: true }));
                    element.dispatchEvent(new Event('change', { bubbles: true }));
                };

                // Wait for form to be ready, then fill and submit
                const fillForm = () => {
                    const emailInput = document.querySelector('input[name="email"], input[type="email"], input[id*="email"], input[id*="username"]');
                    const passInput = document.querySelector('input[name="password"], input[type="password"]');
                    if (emailInput && passInput) {
                        setNativeValue(emailInput, creds[0]);
                        setNativeValue(passInput, creds[1]);
                        console.log('[CAPTCHA] Credentials restored to form, auto-submitting...');

                        // Find and click submit button after a short delay
                        setTimeout(() => {
                            const submitBtn = document.querySelector('button[type="submit"]');
                            if (submitBtn) {
                                console.log('[CAPTCHA] Auto-clicking submit button');
                                submitBtn.click();
                            }
                        }, 500);
                    } else {
                        // Form not ready, try again
                        setTimeout(fillForm, 500);
                    }
                };
                setTimeout(fillForm, 1500);  // Give page time to load
            }
        } catch (e) {
            // Ignore - might not be on account page
        }
    })();

    // Listen for captcha completion via postMessage
    window.addEventListener('message', async (event) => {
        // Only log non-spammy messages
        if (event.data && event.data.type && !['init', 'onload', 'pm_height'].includes(event.data.type)) {
            console.log('[CAPTCHA] postMessage received:', event.origin, JSON.stringify(event.data).substring(0, 200));
        }

        // Proton's captcha sends HUMAN_VERIFICATION_SUCCESS when complete
        if (event.data && event.data.type === 'HUMAN_VERIFICATION_SUCCESS' && event.data.payload) {
            const token = event.data.payload.token;
            const tokenType = event.data.payload.type || 'captcha';
            console.log('[CAPTCHA] Verification successful, storing token and returning');
            captchaPending = false;

            // Store in Rust memory (zero trust - cleared after single use)
            try {
                await window.__TAURI__.core.invoke('store_verification_token', {
                    token: token,
                    tokenType: tokenType
                });
                console.log('[CAPTCHA] Token stored, navigating back');
                window.location.href = 'tauri://localhost/account/';
            } catch (e) {
                console.error('[CAPTCHA] Failed to store token:', e);
            }
        }

        // hCaptcha sends pm_captcha with the token directly
        if (event.data && event.data.type === 'pm_captcha' && event.data.token) {
            const token = event.data.token;
            console.log('[CAPTCHA] pm_captcha received, storing token');
            captchaPending = false;

            try {
                await window.__TAURI__.core.invoke('store_verification_token', {
                    token: token,
                    tokenType: 'captcha'
                });
                console.log('[CAPTCHA] Token stored, navigating back');
                window.location.href = 'tauri://localhost/account/';
            } catch (e) {
                console.error('[CAPTCHA] Failed to store token:', e);
            }
        }
    });

    // Block captcha iframe loading - we navigate to captcha as top-level instead
    const isCaptchaUrl = (src) => {
        return src && src.includes('/api/core/v4/captcha');
    };

    // Intercept iframe src to prevent broken captcha iframes
    // (captcha only works as top-level document in WebKitGTK)
    const origSetAttr = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) {
        if (this.tagName === 'IFRAME' && name === 'src' && isCaptchaUrl(value)) {
            console.log('[CAPTCHA] Blocking iframe - captcha handled via top-level navigation');
            return; // Block - we navigate to captcha as top-level document instead
        }
        return origSetAttr.call(this, name, value);
    };

    const iframeSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'src');
    Object.defineProperty(HTMLIFrameElement.prototype, 'src', {
        set: function(val) {
            if (isCaptchaUrl(val)) {
                console.log('[CAPTCHA] Blocking iframe src - captcha handled via top-level navigation');
                return; // Block
            }
            iframeSrcDescriptor.set.call(this, val);
        },
        get: iframeSrcDescriptor.get
    });

    // Log Worker creation and fix paths for account app
    const OrigWorker = window.Worker;
    window.Worker = function(url, options) {
        let fixedUrl = url;
        // If we're on /account/ and worker uses /assets/ path, redirect to /account/assets/
        if (window.location.pathname.startsWith('/account') && typeof url === 'string') {
            if (url.includes('/assets/') && !url.includes('/account/assets/')) {
                fixedUrl = url.replace('/assets/', '/account/assets/');
                console.log('[WORKER] Fixed path:', url, '->', fixedUrl);
            }
        }
        console.log('[WORKER] Creating worker:', fixedUrl);
        const worker = new OrigWorker(fixedUrl, options);
        worker.onerror = function(e) {
            console.error('[WORKER ERROR]', e.message, e.filename, e.lineno);
        };
        return worker;
    };

    // Redirect console to Rust
    const origLog = console.log;
    const origError = console.error;
    const origWarn = console.warn;

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

    // Catch unhandled errors
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

    const originalFetch = window.fetch;

    window.fetch = async function(input, init = {}) {
        let url = typeof input === 'string' ? input : (input.url || String(input));

        // Skip IPC calls for logging
        if (!url.startsWith('ipc://')) {
            sendToRust('FETCH', [init.method || 'GET', url]);
        }

        // Only proxy API calls
        if (!url.includes('/api/')) {
            return originalFetch.call(window, input, init).then(r => {
                // Skip logging IPC calls to reduce noise
                if (!url.startsWith('ipc://')) {
                    // Log non-200 responses as potential issues
                    if (r.status !== 200) {
                        sendToRust('NATIVE_STATUS', [r.status, url]);
                    }
                }
                return r;
            }).catch(e => {
                if (!url.startsWith('ipc://')) {
                    sendToRust('NATIVE_ERR', [url, e.message || e]);
                }
                throw e;
            });
        }

        const method = init.method || 'GET';
        const headers = {};

        if (init.headers) {
            if (init.headers instanceof Headers) {
                init.headers.forEach((v, k) => headers[k] = v);
            } else if (Array.isArray(init.headers)) {
                init.headers.forEach(([k, v]) => headers[k] = v);
            } else {
                Object.assign(headers, init.headers);
            }
        }

        let body = null;
        if (init.body) {
            body = typeof init.body === 'string' ? init.body : JSON.stringify(init.body);
        }

        try {
            // Ensure all header values are strings
            const cleanHeaders = {};
            for (const [k, v] of Object.entries(headers)) {
                cleanHeaders[k] = String(v);
            }

            // Check for pending verification token (for auth retry after captcha)
            // Must match /api/core/v4/auth exactly, NOT /auth/cookies or /auth/info
            if (url.includes('/api/core/v4/auth') && !url.includes('/auth/cookies') && !url.includes('/auth/info')) {
                const verification = await window.__TAURI__.core.invoke('get_and_clear_verification_token');
                if (verification) {
                    console.log('[CAPTCHA] Adding verification headers to auth request');
                    cleanHeaders['x-pm-human-verification-token'] = verification[0];
                    cleanHeaders['x-pm-human-verification-token-type'] = verification[1];
                }
            }

            const cleanBody = body ? String(body) : null;
            const response = await window.__TAURI__.core.invoke('proxy_request', {
                request: { method, url, headers: cleanHeaders, body: cleanBody }
            });

            const respHeaders = new Headers();
            for (const [k, v] of Object.entries(response.headers || {})) {
                try { respHeaders.set(k, v); } catch(e) {}
            }

            // Apply Set-Cookie headers to WebView (needed for session decryption)
            if (response.headers && response.headers['x-set-cookie']) {
                const cookies = response.headers['x-set-cookie'].split('|||');
                for (const cookie of cookies) {
                    try {
                        // Extract just the cookie name=value part (before first ;)
                        const cookiePart = cookie.split(';')[0];
                        document.cookie = cookiePart + '; path=/; SameSite=Lax';
                        console.log('[COOKIE] Set:', cookiePart.split('=')[0]);
                    } catch (e) {
                        console.warn('[COOKIE] Failed to set:', e);
                    }
                }
            }

            // Check for 9001 (captcha required) and navigate to verify page
            if (response.status === 422 && response.body) {
                try {
                    const data = JSON.parse(response.body);
                    if (data.Code === 9001 && data.Details?.HumanVerificationToken && !captchaPending) {
                        captchaPending = true;
                        const token = data.Details.HumanVerificationToken;
                        // Use the WebUrl provided by Proton (points to verify.proton.me)
                        const captchaUrl = data.Details.WebUrl || ('https://verify.proton.me/?methods=captcha&token=' + encodeURIComponent(token));
                        console.log('[CAPTCHA] Detected 9001, navigating to:', captchaUrl);

                        // Try to capture current login credentials from form before navigating
                        try {
                            const emailInput = document.querySelector('input[name="email"], input[type="email"], input[id*="email"], input[id*="username"]');
                            const passInput = document.querySelector('input[name="password"], input[type="password"]');
                            if (emailInput?.value && passInput?.value) {
                                console.log('[CAPTCHA] Saving login credentials for after captcha');
                                await window.__TAURI__.core.invoke('store_login_credentials', {
                                    username: emailInput.value,
                                    password: passInput.value
                                });
                            }
                        } catch (e) {
                            console.warn('[CAPTCHA] Could not save credentials:', e);
                        }

                        // Navigate to REAL verify page as top-level document
                        // This is the ONLY way hCaptcha works in WebKitGTK
                        window.__TAURI__.core.invoke('navigate_to_captcha', {
                            captchaUrl: captchaUrl,
                            returnUrl: window.location.href
                        }).catch(err => {
                            console.error('[CAPTCHA] Failed to navigate:', err);
                            captchaPending = false;
                        });
                    }
                } catch (e) {}
            }

            return new Response(response.body, {
                status: response.status,
                headers: respHeaders
            });
        } catch (err) {
            console.error('[Proxy Error]', url, err);
            throw new TypeError('Network request failed: ' + err);
        }
    };

    // Also intercept XMLHttpRequest
    const OrigXHR = window.XMLHttpRequest;
    window.XMLHttpRequest = function() {
        const xhr = new OrigXHR();
        const origOpen = xhr.open;
        const origSend = xhr.send;
        let method = 'GET', url = '', headers = {};

        xhr.open = function(m, u, ...args) {
            method = m;
            url = u;
            return origOpen.apply(this, [m, u, ...args]);
        };

        const origSetHeader = xhr.setRequestHeader;
        xhr.setRequestHeader = function(k, v) {
            headers[k] = v;
            return origSetHeader.call(this, k, v);
        };

        xhr.send = function(body) {
            if (!url.includes('/api/')) {
                return origSend.call(this, body);
            }

            console.log('[XHR Proxy]', method, url);

            window.__TAURI__.core.invoke('proxy_request', {
                request: { method, url, headers, body: body || null }
            }).then(response => {
                Object.defineProperty(xhr, 'status', { value: response.status });
                Object.defineProperty(xhr, 'responseText', { value: response.body });
                Object.defineProperty(xhr, 'response', { value: response.body });
                Object.defineProperty(xhr, 'readyState', { value: 4 });
                xhr.dispatchEvent(new Event('readystatechange'));
                xhr.dispatchEvent(new Event('load'));
            }).catch(err => {
                console.error('[XHR Proxy Error]', err);
                xhr.dispatchEvent(new Event('error'));
            });
        };

        return xhr;
    };

    console.log('[Tauri] Fetch + XHR proxy installed');

    // Debug: Log all localStorage keys related to sessions
    try {
        const allKeys = Object.keys(localStorage);
        const sessionKeys = allKeys.filter(k => k.startsWith('ps-'));
        console.log('[STORAGE] pathname:', window.location.pathname, 'localStorage keys:', allKeys.length, 'sessions:', sessionKeys.join(',') || 'none');
    } catch(e) {}

    // Track script load errors
    window.addEventListener('error', (e) => {
        if (e.target && e.target.tagName === 'SCRIPT') {
            console.error('[SCRIPT ERROR]', e.target.src);
        }
    }, true);
})();
"#;

            let app_handle_nav = app.handle().clone();
            let _window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                .title("Proton Drive")
                .inner_size(1200.0, 800.0)
                .min_inner_size(800.0, 600.0)
                .initialization_script(init_script)
                .devtools(true)  // Enable right-click -> Inspect
                .on_download(|_webview, event| {
                    use tauri::webview::DownloadEvent;
                    match event {
                        DownloadEvent::Requested { url, destination } => {
                            // Set download destination to ~/Downloads
                            if let Some(home) = dirs::home_dir() {
                                let downloads_dir = home.join("Downloads");
                                let url_str = url.as_str();
                                if let Some(filename) = url_str.split('/').last() {
                                    // Remove query params from filename
                                    let clean_name = filename.split('?').next().unwrap_or(filename);
                                    *destination = downloads_dir.join(clean_name);
                                    println!("[Download] {} -> {:?}", url_str, destination);
                                }
                            }
                            true // Allow download
                        }
                        DownloadEvent::Finished { success, .. } => {
                            println!("[Download] Finished, success: {}", success);
                            true
                        }
                        _ => true
                    }
                })
                .on_navigation(move |url| {
                    let url_str = url.as_str();
                    println!("[Navigation] {}", url_str);

                    // Intercept blob: URLs for downloads
                    if url.scheme() == "blob" {
                        println!("[Download] Intercepting blob navigation");
                        let blob_url = url_str.to_string();
                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            let js = format!(r#"
                                (async function() {{
                                    const blobUrl = "{}";
                                    const blob = window.__blobUrls?.get(blobUrl);
                                    if (blob) {{
                                        const filename = window.__pendingDownloadName || 'download';
                                        console.log('[Download] Saving blob:', filename, 'size:', blob.size);
                                        const buffer = await blob.arrayBuffer();
                                        const bytes = Array.from(new Uint8Array(buffer));
                                        const path = await window.__TAURI__.core.invoke('save_download', {{
                                            filename: filename,
                                            data: bytes
                                        }});
                                        console.log('[Download] Saved to:', path);
                                    }} else {{
                                        console.error('[Download] Blob not found:', blobUrl);
                                    }}
                                }})();
                            "#, blob_url);
                            tauri::async_runtime::spawn(async move {
                                let _ = window.eval(&js);
                            });
                        }
                        return false; // Block blob navigation
                    }

                    // Rewrite /login paths to /account/ (local SSO)
                    // Add product=drive to tell account app to redirect to Drive after login
                    if url.path().starts_with("/login") {
                        // Build query with product=drive
                        let mut query_parts: Vec<String> = vec!["product=drive".to_string()];
                        if let Some(q) = url.query() {
                            // Filter out session-expired stuff, keep other params
                            for part in q.split('&') {
                                if !part.starts_with("reason=") && !part.starts_with("type=") {
                                    query_parts.push(part.to_string());
                                }
                            }
                        }
                        let query = format!("?{}", query_parts.join("&"));
                        let local_url = format!("tauri://localhost/account/{}", query);
                        println!("[SSO] Rewriting /login to account app: {}", local_url);

                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            let url_clone = local_url.clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = window.navigate(url_clone.parse().unwrap());
                            });
                        }
                        return false; // Block original navigation
                    }

                    // Rewrite account.proton.me to local /account/ path
                    if url.host_str() == Some("account.proton.me") {
                        let path = url.path();
                        let query = url.query().map(|q| format!("?{}", q)).unwrap_or_default();
                        let local_url = format!("tauri://localhost/account{}{}", path, query);
                        println!("[SSO] Rewriting to local: {}", local_url);

                        // Navigate to local account app
                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            let url_clone = local_url.clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = window.navigate(url_clone.parse().unwrap());
                            });
                        }
                        return false; // Block original navigation
                    }

                    // Rewrite drive.proton.me back to local root
                    if url.host_str() == Some("drive.proton.me") {
                        let path = url.path();
                        let query = url.query().map(|q| format!("?{}", q)).unwrap_or_default();
                        let local_url = format!("tauri://localhost{}{}", path, query);
                        println!("[SSO] Rewriting drive.proton.me to local: {}", local_url);

                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            let url_clone = local_url.clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = window.navigate(url_clone.parse().unwrap());
                            });
                        }
                        return false;
                    }

                    // After successful login, account app navigates to account.localhost/u/X/drive/...
                    // Extract the user ID and redirect to Drive with user context
                    if url.host_str() == Some("account.localhost") {
                        let path = url.path();
                        // Extract /u/X/ from path like /u/0/drive/account
                        let user_path = if path.starts_with("/u/") {
                            if let Some(end) = path[3..].find('/') {
                                format!("/u/{}/", &path[3..3+end])
                            } else {
                                "/".to_string()
                            }
                        } else {
                            "/".to_string()
                        };
                        let drive_url = format!("tauri://localhost{}", user_path);
                        println!("[SSO] Login complete, redirecting to: {}", drive_url);

                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            tauri::async_runtime::spawn(async move {
                                tokio::time::sleep(std::time::Duration::from_millis(300)).await;
                                let _ = window.navigate(drive_url.parse().unwrap());
                            });
                        }
                        return false;
                    }

                    // Allow hCaptcha domains for the captcha widget to work
                    // (must be checked BEFORE the "left captcha" detection)
                    if let Some(host) = url.host_str() {
                        if host == "hcaptcha.com" || host.ends_with(".hcaptcha.com") {
                            println!("[CAPTCHA] Allowing hCaptcha resource: {}", url_str);
                            return true;
                        }
                    }

                    // Track captcha page state and allow captcha-related URLs
                    let is_captcha_url = match url.host_str() {
                        Some("mail.proton.me") => url.path().starts_with("/api/core/v4/captcha") || url.path().starts_with("/captcha/"),
                        Some("verify.proton.me") => true,  // The verify app page
                        Some("verify-api.proton.me") => true,  // The API that serves captcha content
                        _ => false,
                    };

                    if is_captcha_url {
                        println!("[CAPTCHA] Entering captcha page: {}", url_str);
                        ON_CAPTCHA_PAGE.store(true, std::sync::atomic::Ordering::SeqCst);
                        return true;
                    }

                    // Detect navigation AWAY from captcha to non-captcha page - means captcha flow completed
                    if ON_CAPTCHA_PAGE.load(std::sync::atomic::Ordering::SeqCst) {
                        // We're leaving the captcha page (not to another captcha/hcaptcha URL)
                        ON_CAPTCHA_PAGE.store(false, std::sync::atomic::Ordering::SeqCst);
                        println!("[CAPTCHA] Left captcha page, returning to account app");

                        // Navigate back to account app to retry auth
                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            tauri::async_runtime::spawn(async move {
                                let _ = window.navigate("tauri://localhost/account/".parse().unwrap());
                            });
                        }
                        return false; // Block whatever navigation triggered this, we'll go to account
                    }

                    // Allow tauri://, about: URLs and API paths (for iframes)
                    url.scheme() == "tauri"
                        || url.scheme() == "about"
                        || url.host_str() == Some("localhost")
                        || url.host_str() == Some("tauri.localhost")
                        || url.path().starts_with("/api/")
                })
                .build()?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![proxy_request, js_log, navigate_to_captcha, get_captcha_return_url, store_verification_token, get_and_clear_verification_token, store_login_credentials, get_and_clear_login_credentials, save_download])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
