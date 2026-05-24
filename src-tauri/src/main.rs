#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use reqwest::cookie::Jar;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};

mod live_sync;
mod proton_navigation;
mod url_log;
mod webview_cookies;
mod webview_storage;

use proton_navigation::{
    account_login_complete_redirect_url, captcha_completion_token, unsupported_app_redirect_url,
};
use url_log::sanitize_url_for_log;
use webview_cookies::{combined_cookie_header, store_webview_cookie};
use webview_storage::{ensure_webview_data_dir, persistent_webview_data_dir};

const PROTON_API_BASE: &str = "https://mail.proton.me";
const ERR_SYNC_NOT_ALLOWED: &str = "Sync operation is not allowed in this context";
const PROXY_REQUEST_TIMEOUT: Duration = Duration::from_secs(45);
const PROXY_CONNECT_TIMEOUT: Duration = Duration::from_secs(15);

static PROXY_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

// Shared HTTP client with cookie jar
struct AppState {
    client: Client,
    cookie_jar: Arc<Jar>,
    sync_manager: live_sync::LiveSyncManager,
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
static PENDING_VERIFICATION: std::sync::Mutex<Option<(String, String)>> =
    std::sync::Mutex::new(None);

// Store login credentials during captcha flow (zero trust - cleared after use)
static PENDING_CREDENTIALS: std::sync::Mutex<Option<(String, String)>> =
    std::sync::Mutex::new(None);

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
async fn navigate_to_captcha(
    app: tauri::AppHandle,
    captcha_url: String,
    return_url: String,
) -> Result<(), String> {
    println!("[CAPTCHA] Starting verification navigation flow");

    // Store return URL
    *CAPTCHA_RETURN_URL.lock().unwrap() = Some(return_url);

    // Navigate main window to captcha (local or external)
    if let Some(window) = app.get_webview_window("main") {
        let url: tauri::Url = captcha_url.parse().map_err(|e| {
            eprintln!("[CAPTCHA] Invalid captcha URL '{}': {e}", captcha_url);
            "Unable to open verification page".to_string()
        })?;
        window.navigate(url).map_err(|e| {
            eprintln!("[CAPTCHA] Navigation to captcha failed: {e}");
            "Unable to open verification page".to_string()
        })?;
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
        .ok_or("Unable to access download location")?;

    // Ensure downloads dir exists
    std::fs::create_dir_all(&downloads_dir).map_err(|e| {
        eprintln!(
            "[Download] Failed to create downloads dir {:?}: {e}",
            downloads_dir
        );
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

#[tauri::command]
fn start_sync(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<live_sync::LiveSyncStatus, String> {
    println!("[Sync] start_sync requested path={}", path);
    ensure_sync_command_allowed(&window)?;
    let sync_root = validate_sync_root_path(&path)?;
    state.sync_manager.start(app, sync_root)?;
    let status = state.sync_manager.status()?;
    println!(
        "[Sync] start_sync active enabled={} folder={}",
        status.enabled,
        status.folder_path.as_deref().unwrap_or("<none>")
    );
    Ok(status)
}

#[tauri::command]
fn stop_sync(
    window: tauri::WebviewWindow,
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<live_sync::LiveSyncStatus, String> {
    println!("[Sync] stop_sync requested");
    ensure_sync_command_allowed(&window)?;
    state.sync_manager.stop()?;
    let status = state.sync_manager.status()?;
    println!("[Sync] stop_sync complete enabled={}", status.enabled);
    Ok(status)
}

#[tauri::command]
fn get_sync_status(
    window: tauri::WebviewWindow,
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<live_sync::LiveSyncStatus, String> {
    ensure_sync_command_allowed(&window)?;
    let status = state.sync_manager.status()?;
    println!(
        "[Sync] get_sync_status enabled={} folder={}",
        status.enabled,
        status.folder_path.as_deref().unwrap_or("<none>")
    );
    Ok(status)
}

#[tauri::command]
fn handle_remote_update(
    window: tauri::WebviewWindow,
    state: tauri::State<'_, Arc<AppState>>,
    change: live_sync::RemoteSyncChange,
) -> Result<String, String> {
    println!(
        "[Sync] handle_remote_update action={} path={}",
        change.action, change.relative_path
    );
    ensure_sync_command_allowed(&window)?;
    let target = state.sync_manager.apply_remote_change(change)?;
    println!("[Sync] handle_remote_update applied target={}", target);
    Ok(target)
}

#[tauri::command]
async fn proxy_request(
    window: tauri::WebviewWindow,
    state: tauri::State<'_, Arc<AppState>>,
    request: ProxyRequest,
) -> Result<ProxyResponse, String> {
    // Build the target URL - extract path from various URL formats
    let url = if request.url.starts_with("https://localhost/api/")
        || request.url.starts_with("http://localhost/api/")
    {
        // Rewrite localhost API calls to Proton
        format!(
            "{}{}",
            PROTON_API_BASE,
            &request.url[request.url.find("/api").unwrap()..]
        )
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

    let request_id = PROXY_REQUEST_ID.fetch_add(1, Ordering::Relaxed);
    let started_at = Instant::now();
    let sanitized_url = sanitize_url_for_log(&url);
    println!("[Proxy][{}] {} {} start", request_id, method, sanitized_url);

    let target_url = tauri::Url::parse(&url).map_err(|e| {
        eprintln!(
            "[Proxy] invalid target URL {}: {e}",
            sanitized_url
        );
        "Invalid request URL".to_string()
    })?;

    let mut req = state.client.request(method, &url).timeout(PROXY_REQUEST_TIMEOUT);
    if let Some(cookie_header) = combined_cookie_header(&window, &state.cookie_jar, &target_url) {
        req = req.header(reqwest::header::COOKIE, cookie_header);
    }

    // Forward headers from frontend. Cookies come from WebKit's native jar.
    for (key, value) in &request.headers {
        let k = key.to_lowercase();
        if k != "host" && k != "cookie" {
            req = req.header(key.as_str(), value.as_str());
        }
    }

    if let Some(ref body) = request.body {
        req = req.body(body.clone());
    }

    let resp = match req.send().await {
        Ok(resp) => resp,
        Err(e) => {
            let elapsed_ms = started_at.elapsed().as_millis();
            let status = if e.is_timeout() { 504 } else { 502 };
            eprintln!(
                "[Proxy][{}] {} {} failed status={} elapsed_ms={} error={}",
                request_id, request.method, sanitized_url, status, elapsed_ms, e
            );
            return Ok(ProxyResponse {
                status,
                headers: HashMap::new(),
                body: format!(
                    "{{\"Error\":\"Native proxy request failed\",\"Status\":{},\"Timeout\":{}}}",
                    status,
                    e.is_timeout()
                ),
            });
        }
    };
    let status = resp.status().as_u16();

    // Forward response headers, but keep Set-Cookie inside WebKit's native jar.
    let mut resp_headers = HashMap::new();
    for (name, value) in resp.headers().iter() {
        if let Ok(v) = value.to_str() {
            if name.as_str().eq_ignore_ascii_case("set-cookie") {
                store_webview_cookie(&window, &target_url, v);
            } else {
                resp_headers.insert(name.to_string(), v.to_string());
            }
        }
    }

    let body = match resp.text().await {
        Ok(body) => body,
        Err(e) => {
            let elapsed_ms = started_at.elapsed().as_millis();
            eprintln!(
                "[Proxy][{}] {} {} body_read_failed elapsed_ms={} error={}",
                request_id, request.method, sanitized_url, elapsed_ms, e
            );
            String::new()
        }
    };

    println!(
        "[Proxy][{}] {} <- {} elapsed_ms={} body={}",
        request_id,
        status,
        sanitized_url,
        started_at.elapsed().as_millis(),
        body.len()
    );

    Ok(ProxyResponse {
        status,
        headers: resp_headers,
        body,
    })
}

fn ensure_sync_command_allowed(window: &tauri::WebviewWindow) -> Result<(), String> {
    let current_url = window.url().map_err(|e| {
        eprintln!("[Sync] failed to read window URL: {e}");
        ERR_SYNC_NOT_ALLOWED.to_string()
    })?;

    let host = current_url.host_str().unwrap_or_default();
    let is_allowed =
        current_url.scheme() == "tauri" && (host == "localhost" || host == "tauri.localhost");

    if !is_allowed {
        eprintln!(
            "[Sync] rejected command from origin scheme={} host={}",
            current_url.scheme(),
            host
        );
        return Err(ERR_SYNC_NOT_ALLOWED.to_string());
    }

    Ok(())
}

fn validate_sync_root_path(path: &str) -> Result<PathBuf, String> {
    let canonical = PathBuf::from(path).canonicalize().map_err(|e| {
        eprintln!("[Sync] invalid sync root path '{}': {e}", path);
        "Invalid sync folder".to_string()
    })?;

    let home = dirs::home_dir().ok_or("Invalid sync folder")?;
    if !canonical.starts_with(&home) {
        eprintln!(
            "[Sync] rejected sync root outside home: path={:?} home={:?}",
            canonical, home
        );
        return Err("Invalid sync folder".to_string());
    }

    Ok(canonical)
}

fn main() {
    // Fix WebKitGTK EGL/GPU issues on various Linux configurations
    std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
    std::env::set_var("WEBKIT_FORCE_SANDBOX", "0");
    std::env::set_var("GDK_GL", "disable");
    std::env::set_var("GSK_RENDERER", "cairo");

    // Create shared client with cookie jar
    let cookie_jar = Arc::new(Jar::default());
    let state = Arc::new(AppState {
        client: Client::builder()
            .cookie_provider(cookie_jar.clone())
            .connect_timeout(PROXY_CONNECT_TIMEOUT)
            .timeout(PROXY_REQUEST_TIMEOUT)
            .build()
            .expect("Failed to create HTTP client"),
        cookie_jar,
        sync_manager: live_sync::LiveSyncManager::default(),
    });

    let startup_sync_state = Arc::clone(&state);

    tauri::Builder::default()
        .manage(state)
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .setup(move |app| {
            let webview_data_dir = persistent_webview_data_dir(app.path().app_data_dir()?);
            ensure_webview_data_dir(&webview_data_dir)?;
            println!(
                "[Storage] Using persistent WebView data directory: {:?}",
                webview_data_dir
            );

            // MULTI-DISTRO WORKER COMPATIBILITY
            // Different distros use different WebKitGTK builds with varying Worker support
            // Use DISTRO_TYPE env var at build time to determine Worker handling
            //
            // Distro Support Matrix:
            // - appimage: Bundled WebKitGTK → Workers work → Use native
            // - rpm/deb:  System WebKitGTK → "operation is insecure" → Override
            // - flatpak/snap: Sandboxed → Override as safe default

            let worker_init = match option_env!("DISTRO_TYPE") {
                Some("appimage") | Some("aur") => {
                    // Native Workers supported - no override needed
                    r#"
    console.log('[INIT] AppImage/AUR build - using native Workers');
"#
                }
                Some("rpm") | Some("deb") | Some("flatpak") | Some("snap") | None => {
                    // System WebKitGTK or sandboxed - disable Workers to trigger Proton's built-in fallback
                    r#"
    // Force Proton WebClients to use non-Worker crypto mode
    // Proton WebClients check Worker support and automatically fall back to main-thread crypto
    // Reference: packages/shared/lib/helpers/setupCryptoWorker.ts line 19
    console.log('[INIT] RPM/deb build - disabling Worker support to use main-thread crypto');

    // Set Worker/SharedWorker to undefined - Proton will detect and use fallback mode
    window.Worker = undefined;
    window.SharedWorker = undefined;

    console.log('[INIT] Workers set to undefined - Proton will load crypto API in main thread');
"#
                }
                _ => {
                    // Unknown distro - use safe default (override)
                    r#"
    console.warn('[INIT] Unknown distro - using Worker override as safe default');
    delete window.Worker;
    delete window.SharedWorker;

    // Suppress Worker errors globally
    window.addEventListener('error', function(event) {
        if (event.error && event.error.message && event.error.message.includes('Worker')) {
            event.preventDefault();
            return true;
        }
    }, true);

    const OrigWorker = window.Worker;
    window.Worker = function Worker(url) {
        console.log('[Worker] Blocked - unknown distro, using safe default');
        const err = new Error('Worker not supported');
        err.name = 'SecurityError';
        throw err;
    };
    window.Worker.prototype = OrigWorker ? OrigWorker.prototype : {};

    window.SharedWorker = function SharedWorker(url) {
        console.log('[SharedWorker] Blocked - returning stub');
        const port = {
            postMessage: function() {},
            start: function() {},
            close: function() {},
            addEventListener: function() {},
            removeEventListener: function() {},
            onmessage: null,
            onmessageerror: null
        };
        return {
            port: port,
            onerror: null
        };
    };

    Object.defineProperty(window, 'Worker', {
        value: window.Worker,
        writable: false,
        configurable: false
    });
    Object.defineProperty(window, 'SharedWorker', {
        value: window.SharedWorker,
        writable: false,
        configurable: false
    });
"#
                }
            };

            let init_script = format!(r#"
(function() {{
    {}
"#, worker_init) + r#"

    // Regression guard for post-2FA Drive load:
    // The Tauri asset protocol must load Drive at tauri://localhost/, but the
    // Drive SPA needs a /u/<localID>/ route when a persisted ps-<localID>
    // session exists. If we leave the path at /, Drive treats the session as
    // expired and loops back through account login. Rewrite the route before
    // Proton app code runs so React Router starts on the active user route
    // without a full deep-path WebView reload.
    try {
        if (window.location.protocol === 'tauri:' && window.location.hostname === 'localhost' && window.location.pathname === '/') {
            const sessionKey = Object.keys(localStorage).find((key) => /^ps-\d+$/.test(key));
            const localId = sessionKey && sessionKey.slice(3);
            if (localId) {
                history.replaceState({}, '', `/u/${localId}/`);
                console.log('[SSO] Restored Drive user route before app init:', `/u/${localId}/`);
            }
        }
    } catch (e) {
        console.warn('[SSO] Failed to restore Drive user route:', e);
    }

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
            console.log('[CAPTCHA] Verification successful, returning to account');
            captchaPending = false;

            // External verify pages cannot use Tauri IPC reliably. Return the
            // token through a local URL and let Rust store it before auth retry.
            window.location.href = 'tauri://localhost/account/?hv_token='
                + encodeURIComponent(token)
                + '&hv_type=' + encodeURIComponent(tokenType);
        }

        // hCaptcha sends pm_captcha with the token directly
        if (event.data && event.data.type === 'pm_captcha' && event.data.token) {
            const token = event.data.token;
            console.log('[CAPTCHA] pm_captcha received, returning to account');
            captchaPending = false;

            window.location.href = 'tauri://localhost/account/?hv_token='
                + encodeURIComponent(token)
                + '&hv_type=captcha';
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

    // Zero-trust startup diagnostics: the app has repeatedly regressed into
    // a visible loading spinner with no actionable UI state. Keep this
    // user-facing so a frozen WebView shows what request/state is blocking.
    const startupDiagnostics = {
        startedAt: Date.now(),
        pendingProxy: new Map(),
        lastLocation: window.location.href,
        panel: null,
        ensurePanel() {
            if (this.panel || !document.body) return this.panel;
            const panel = document.createElement('pre');
            panel.id = 'protondrive-startup-diagnostics';
            panel.style.cssText = [
                'position:fixed',
                'left:12px',
                'right:12px',
                'bottom:12px',
                'z-index:2147483647',
                'max-height:34vh',
                'overflow:auto',
                'white-space:pre-wrap',
                'font:12px/1.4 monospace',
                'padding:10px',
                'border-radius:8px',
                'border:1px solid rgba(255,255,255,.25)',
                'background:rgba(0,0,0,.86)',
                'color:#fff',
                'box-shadow:0 8px 32px rgba(0,0,0,.35)',
                'display:none'
            ].join(';');
            document.body.appendChild(panel);
            this.panel = panel;
            return panel;
        },
        snapshot(label, forceVisible = false) {
            let sessionKeys = [];
            try { sessionKeys = Object.keys(localStorage).filter(k => k.startsWith('ps-')); } catch {}
            const pending = Array.from(this.pendingProxy.values()).map(entry => {
                return `${Math.round((Date.now() - entry.startedAt) / 1000)}s ${entry.method} ${entry.url}`;
            });
            const lines = [
                `[StartupDiag] ${label}`,
                `url=${window.location.href}`,
                `ready=${document.readyState} visible=${document.visibilityState}`,
                `sessions=${sessionKeys.join(',') || 'none'}`,
                `pendingProxy=${pending.length}`,
                ...pending.slice(0, 8)
            ];
            sendToRust('STARTUP_DIAG', lines);
            const panel = this.ensurePanel();
            if (panel) {
                panel.textContent = lines.join('\n');
                panel.style.display = (forceVisible || pending.length > 0) ? 'block' : 'none';
            }
        },
        trackRequest(id, method, url) {
            this.pendingProxy.set(id, { method, url, startedAt: Date.now() });
            setTimeout(() => {
                if (this.pendingProxy.has(id)) {
                    this.snapshot('proxy request still pending after 10s', true);
                }
            }, 10000);
            setTimeout(() => {
                if (this.pendingProxy.has(id)) {
                    this.snapshot('proxy request still pending after 30s', true);
                }
            }, 30000);
        },
        finishRequest(id) {
            this.pendingProxy.delete(id);
            if (this.pendingProxy.size === 0) this.snapshot('proxy idle');
        }
    };
    window.__PROTONDRIVE_STARTUP_DIAGNOSTICS__ = startupDiagnostics;
    document.addEventListener('DOMContentLoaded', () => startupDiagnostics.snapshot('DOMContentLoaded'));
    window.addEventListener('load', () => startupDiagnostics.snapshot('window load'));
    window.addEventListener('pageshow', () => startupDiagnostics.snapshot('pageshow'));
    setTimeout(() => startupDiagnostics.snapshot('startup watchdog 8s', true), 8000);
    setTimeout(() => startupDiagnostics.snapshot('startup watchdog 30s', true), 30000);

    const originalFetch = window.fetch;
    const responseBodyForStatus = (status, body) => {
        return [204, 205, 304].includes(status) ? null : (body ?? '');
    };
    const isStorageBlockUrl = (url) => {
        try {
            const parsed = new URL(url, window.location.href);
            return parsed.pathname.includes('/storage/blocks');
        } catch {
            return String(url || '').includes('/storage/blocks');
        }
    };

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

    const collectHeaders = (input, init) => {
        const headers = {};
        const mergeHeaders = (source) => {
            if (!source) return;
            const sourceHeaders = new Headers(source);
            sourceHeaders.forEach((value, key) => headers[key] = value);
        };

        if (input instanceof Request) {
            mergeHeaders(input.headers);
        }
        mergeHeaders(init?.headers);

        return headers;
    };

    const collectFetchRequest = async (input, init = {}) => {
        const request = input instanceof Request ? input : null;
        const method = (init.method || request?.method || 'GET').toUpperCase();
        const headers = collectHeaders(request || input, init);
        const hasInitBody = Object.prototype.hasOwnProperty.call(init, 'body') && init.body != null;
        let body = null;

        if (method !== 'GET' && method !== 'HEAD') {
            if (hasInitBody) {
                body = await requestBodyToString(init.body);
            } else if (request) {
                try {
                    body = await request.clone().text();
                } catch (e) {
                    console.warn('[Proxy] Unable to read Request body:', e);
                }
            }
        }

        return { method, headers, body };
    };

    window.fetch = async function(input, init = {}) {
        let url = typeof input === 'string' ? input : (input.url || String(input));

        // Fix protocol-relative URLs (//assets/... or //account/assets/...)
        // These would resolve to tauri://assets/... which is invalid
        if (typeof url === 'string' && url.startsWith('//')) {
            url = url.substring(1);  // Remove one slash to make it absolute: /assets/...
            console.log('[FETCH] Fixed protocol-relative URL to:', url);
        }

        // Skip IPC calls for logging
        if (!url.startsWith('ipc://')) {
            sendToRust('FETCH', [init.method || 'GET', url]);
        }

        // Only proxy API calls
        if (!url.includes('/api/')) {
            // For fetch calls, if we've fixed the URL from // to /, update the input
            let fetchInput = input;
            if (typeof input === 'string' && input !== url) {
                fetchInput = url;
            } else if (typeof input === 'object' && input.url) {
                fetchInput = new Request(url, input);
            }
            const method = (init.method || (input instanceof Request ? input.method : 'GET') || 'GET').toUpperCase();
            const storageBlockUrl = isStorageBlockUrl(url);
            if (storageBlockUrl) {
                let bodyLength = 0;
                try {
                    const collected = await collectFetchRequest(input, init);
                    bodyLength = collected.body ? String(collected.body).length : 0;
                } catch (e) {
                    console.warn('[StorageBlocks] Unable to inspect request body:', e);
                }
                sendToRust('STORAGE_BLOCK_REQ', [method, url, 'body=' + bodyLength]);
            }

            return originalFetch.call(window, fetchInput, init).then(r => {
                // Skip logging IPC calls to reduce noise
                if (!url.startsWith('ipc://')) {
                    // Log non-200 responses as potential issues
                    if (r.status !== 200) {
                        sendToRust('NATIVE_STATUS', [r.status, url]);
                    }
                    if (storageBlockUrl) {
                        const length = r.headers?.get?.('content-length') || 'unknown';
                        sendToRust('STORAGE_BLOCK_RES', [method, r.status, url, 'content-length=' + length]);
                    }
                }
                return r;
            }).catch(e => {
                if (!url.startsWith('ipc://')) {
                    sendToRust('NATIVE_ERR', [url, e.message || e]);
                    if (storageBlockUrl) {
                        sendToRust('STORAGE_BLOCK_ERR', [method, url, e.message || e]);
                    }
                }
                throw e;
            });
        }

        let proxyTraceId = null;
        try {
            const proxiedRequest = await collectFetchRequest(input, init);

            // Ensure all header values are strings
            const cleanHeaders = {};
            for (const [k, v] of Object.entries(proxiedRequest.headers)) {
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

            const cleanBody = proxiedRequest.body == null ? null : String(proxiedRequest.body);
            proxyTraceId = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
            startupDiagnostics.trackRequest(proxyTraceId, proxiedRequest.method, url);
            sendToRust('PROXY_REQ', [proxyTraceId, proxiedRequest.method, url, 'body=' + (cleanBody ? cleanBody.length : 0)]);
            const response = await window.__TAURI__.core.invoke('proxy_request', {
                request: { method: proxiedRequest.method, url, headers: cleanHeaders, body: cleanBody }
            });
            startupDiagnostics.finishRequest(proxyTraceId);
            sendToRust('PROXY_RES', [proxyTraceId, response.status, url, 'body=' + ((response.body || '').length)]);

            const respHeaders = new Headers();
            for (const [k, v] of Object.entries(response.headers || {})) {
                try { respHeaders.set(k, v); } catch(e) {}
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

            return new Response(responseBodyForStatus(response.status, response.body), {
                status: response.status,
                headers: respHeaders
            });
        } catch (err) {
            if (proxyTraceId) startupDiagnostics.finishRequest(proxyTraceId);
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

            requestBodyToString(body).then((serializedBody) => window.__TAURI__.core.invoke('proxy_request', {
                request: {
                    method,
                    url,
                    headers,
                    body: serializedBody == null ? null : String(serializedBody)
                }
            })).then(response => {
                Object.defineProperty(xhr, 'status', { value: response.status });
                Object.defineProperty(xhr, 'statusText', { value: String(response.status) });
                Object.defineProperty(xhr, 'responseText', { value: response.body });
                Object.defineProperty(xhr, 'response', { value: response.body });
                Object.defineProperty(xhr, 'responseURL', { value: url });
                Object.defineProperty(xhr, 'readyState', { value: 4 });
                xhr.dispatchEvent(new Event('readystatechange'));
                xhr.dispatchEvent(new Event('load'));
                xhr.dispatchEvent(new Event('loadend'));
            }).catch(err => {
                console.error('[XHR Proxy Error]', err);
                xhr.dispatchEvent(new Event('error'));
                xhr.dispatchEvent(new Event('loadend'));
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

    // Track script load errors and fetch the scripts to see HTTP status
    window.addEventListener('error', async (e) => {
        if (e.target && e.target.tagName === 'SCRIPT') {
            console.error('[SCRIPT ERROR]', e.target.src);
            try {
                const response = await fetch(e.target.src);
                console.error('[SCRIPT ERROR] HTTP Status:', response.status, response.statusText);
                const text = await response.text();
                console.error('[SCRIPT ERROR] Response preview:', text.substring(0, 200));
            } catch (err) {
                console.error('[SCRIPT ERROR] Fetch failed:', err.message);
            }
        }
    }, true);
})();
"#;

            let app_handle_nav = app.handle().clone();
            let _window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                .title("Proton Drive")
                .inner_size(1200.0, 800.0)
                .min_inner_size(800.0, 600.0)
                .data_directory(webview_data_dir)
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

                    // After successful login/2FA, account.localhost lands on a
                    // user-scoped Drive handoff route. Redirect to Drive root,
                    // not /u/<id>/; deep tauri://localhost paths break the
                    // WebKitGTK asset protocol/IPC bridge and freeze the app.
                    // Force account to about:blank before loading Drive. Direct
                    // same-origin handoffs to tauri://localhost/ can update the
                    // URL while leaving the account document alive on WebKitGTK,
                    // so the Drive init script never reinstalls IPC.
                    if let Some(drive_url) = account_login_complete_redirect_url(url) {
                        println!("[SSO] Login complete, redirecting to: {}", drive_url);

                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            tauri::async_runtime::spawn(async move {
                                let _ = window.eval("window.location.replace('about:blank');");
                                tokio::time::sleep(std::time::Duration::from_millis(250)).await;
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

                    // Regression guard for login/2FA:
                    // Captcha completion is ONLY valid when injected JS returns to
                    // tauri://localhost/account/?hv_token=...&hv_type=...
                    // Do not infer completion from "leaving" verify.proton.me.
                    // WebKitGTK emits captcha-internal about:blank/verify-api
                    // navigations while verification is still active; handling
                    // those as completion caused post-2FA freezes.
                    if ON_CAPTCHA_PAGE.load(std::sync::atomic::Ordering::SeqCst)
                    {
                        if let Some((token, token_type)) = captcha_completion_token(url) {
                            ON_CAPTCHA_PAGE.store(false, std::sync::atomic::Ordering::SeqCst);
                            println!("[CAPTCHA] Storing token from completion URL");
                            *PENDING_VERIFICATION.lock().unwrap() = Some((token, token_type));

                            if let Some(window) = app_handle_nav.get_webview_window("main") {
                                tauri::async_runtime::spawn(async move {
                                    let _ = window.navigate("tauri://localhost/account/".parse().unwrap());
                                });
                            }
                            return false;
                        }

                        if url.scheme() == "tauri"
                            && url.host_str() == Some("localhost")
                            && url.path().starts_with("/account/")
                        {
                            println!(
                                "[CAPTCHA] Ignoring account return without verification token: {}",
                                url_str
                            );
                            return false;
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

                    if ON_CAPTCHA_PAGE.load(std::sync::atomic::Ordering::SeqCst)
                        && url.scheme() == "about"
                    {
                        println!("[CAPTCHA] Allowing captcha internal navigation: {}", url_str);
                        return true;
                    }

                    if let Some(local_url) = unsupported_app_redirect_url(url) {
                        println!(
                            "[SSO] Redirecting unsupported Proton app host {} to Drive: {}",
                            url.host_str().unwrap_or("unknown"),
                            local_url
                        );

                        if let Some(window) = app_handle_nav.get_webview_window("main") {
                            let url_clone = local_url.clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = window.navigate(url_clone.parse().unwrap());
                            });
                        }
                        return false;
                    }

                    // Allow tauri://, about: URLs but BLOCK /api/ navigation (API calls should use fetch, not navigate)
                    // Blocking /api/ prevents iframes from trying to load API endpoints which breaks the account app
                    if url.path().starts_with("/api/") {
                        println!("[Navigation] Blocking API navigation (should use fetch): {}", url_str);
                        return false;
                    }

                    url.scheme() == "tauri"
                        || url.scheme() == "about"
                        || url.host_str() == Some("localhost")
                        || url.host_str() == Some("tauri.localhost")
                })
                .build()?;

            if let Ok(path) = std::env::var("PROTONDRIVE_AUTO_SYNC_PATH") {
                println!("[Sync] PROTONDRIVE_AUTO_SYNC_PATH requested path={}", path);
                match validate_sync_root_path(&path)
                    .and_then(|sync_root| startup_sync_state.sync_manager.start(app.handle().clone(), sync_root))
                    .and_then(|_| startup_sync_state.sync_manager.status())
                {
                    Ok(status) => println!(
                        "[Sync] auto-start active enabled={} folder={}",
                        status.enabled,
                        status.folder_path.as_deref().unwrap_or("<none>")
                    ),
                    Err(error) => eprintln!("[Sync] auto-start failed: {}", error),
                }
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            proxy_request,
            js_log,
            navigate_to_captcha,
            get_captcha_return_url,
            store_verification_token,
            get_and_clear_verification_token,
            store_login_credentials,
            get_and_clear_login_credentials,
            save_download,
            // Sync bridge contract:
            // start_sync/get_sync_status/stop_sync are the local folder watcher side.
            // handle_remote_update is the remote-to-local apply side.
            // The frontend owns Proton Drive upload/download semantics and must keep
            // these command names in sync with docs/sync.md and CI regression checks.
            start_sync,
            stop_sync,
            get_sync_status,
            handle_remote_update
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
