#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

mod auth;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use tokio::sync::RwLock;

use auth::{AuthManager, AuthSession, AuthError};

const PROTON_API_BASE: &str = "https://mail.proton.me";

/// Shared application state
struct AppState {
    client: Client,
    auth: AuthManager,
    cookies: RwLock<HashMap<String, String>>,
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

/// Parse Set-Cookie header to extract name=value
fn parse_cookie(set_cookie: &str) -> Option<(String, String)> {
    let parts: Vec<&str> = set_cookie.split(';').collect();
    if let Some(cookie_part) = parts.first() {
        let cookie_parts: Vec<&str> = cookie_part.splitn(2, '=').collect();
        if cookie_parts.len() == 2 {
            return Some((cookie_parts[0].trim().to_string(), cookie_parts[1].trim().to_string()));
        }
    }
    None
}

/// Build Cookie header from stored cookies
fn build_cookie_header(cookies: &HashMap<String, String>) -> String {
    cookies
        .iter()
        .map(|(k, v)| format!("{}={}", k, v))
        .collect::<Vec<_>>()
        .join("; ")
}

/// Main IPC proxy command - handles ALL API requests from frontend
#[tauri::command]
async fn proxy_request(
    state: tauri::State<'_, Arc<AppState>>,
    request: ProxyRequest,
) -> Result<ProxyResponse, String> {
    // Build full URL
    let url = if request.url.starts_with("http") {
        request.url.clone()
    } else {
        format!("{}{}", PROTON_API_BASE, request.url)
    };

    println!("[IPC] {} {}", request.method, url);

    // Parse method
    let method = reqwest::Method::from_bytes(request.method.as_bytes())
        .unwrap_or(reqwest::Method::GET);

    let mut req = state.client.request(method.clone(), &url);

    // Get auth session and add Authorization/UID headers
    let session = state.auth.get_session().await;
    if let Some(ref s) = session {
        req = req.header("x-pm-uid", &s.uid);
        req = req.header("Authorization", format!("{} {}", s.token_type, s.access_token));
    }

    // Add stored cookies (for non-auth cookies)
    {
        let cookies = state.cookies.read().await;
        if !cookies.is_empty() {
            let cookie_header = build_cookie_header(&cookies);
            req = req.header("Cookie", cookie_header);
        }
    }

    // Forward headers from frontend (except auth-related ones we manage)
    for (key, value) in &request.headers {
        let key_lower = key.to_lowercase();
        if key_lower != "cookie"
            && key_lower != "host"
            && key_lower != "authorization"
            && key_lower != "x-pm-uid"
        {
            req = req.header(key.as_str(), value.as_str());
        }
    }

    // Add Proton-specific headers if not present
    if !request.headers.contains_key("x-pm-appversion") {
        req = req.header("x-pm-appversion", "web-drive@5.0.0");
    }
    if !request.headers.contains_key("x-pm-apiversion") {
        req = req.header("x-pm-apiversion", "3");
    }
    req = req.header("Origin", "https://drive.proton.me");
    req = req.header("Referer", "https://drive.proton.me/");

    // Add body if present
    if let Some(ref body) = request.body {
        req = req.body(body.clone());
    }

    // Send request
    let resp = req.send().await.map_err(|e| format!("Request failed: {}", e))?;

    let status = resp.status().as_u16();
    println!("[IPC] Response: {}", status);

    // Handle 401 - try to refresh token
    if status == 401 && session.is_some() {
        println!("[IPC] Got 401, attempting token refresh...");
        match state.auth.refresh_token().await {
            Ok(new_session) => {
                println!("[IPC] Token refreshed, retrying request...");

                // Retry the request with new token
                let mut retry_req = state.client.request(method, &url);
                retry_req = retry_req.header("x-pm-uid", &new_session.uid);
                retry_req = retry_req.header("Authorization", format!("{} {}", new_session.token_type, new_session.access_token));

                // Re-add cookies
                {
                    let cookies = state.cookies.read().await;
                    if !cookies.is_empty() {
                        let cookie_header = build_cookie_header(&cookies);
                        retry_req = retry_req.header("Cookie", cookie_header);
                    }
                }

                // Re-add other headers
                for (key, value) in &request.headers {
                    let key_lower = key.to_lowercase();
                    if key_lower != "cookie"
                        && key_lower != "host"
                        && key_lower != "authorization"
                        && key_lower != "x-pm-uid"
                    {
                        retry_req = retry_req.header(key.as_str(), value.as_str());
                    }
                }

                if !request.headers.contains_key("x-pm-appversion") {
                    retry_req = retry_req.header("x-pm-appversion", "web-drive@5.0.0");
                }
                if !request.headers.contains_key("x-pm-apiversion") {
                    retry_req = retry_req.header("x-pm-apiversion", "3");
                }
                retry_req = retry_req.header("Origin", "https://drive.proton.me");
                retry_req = retry_req.header("Referer", "https://drive.proton.me/");

                if let Some(body) = request.body {
                    retry_req = retry_req.body(body);
                }

                if let Ok(retry_resp) = retry_req.send().await {
                    let retry_status = retry_resp.status().as_u16();
                    println!("[IPC] Retry response: {}", retry_status);

                    // Store cookies from retry response
                    for (name, value) in retry_resp.headers().iter() {
                        if name.as_str().to_lowercase() == "set-cookie" {
                            if let Ok(cookie_str) = value.to_str() {
                                if let Some((k, v)) = parse_cookie(cookie_str) {
                                    let mut cookies = state.cookies.write().await;
                                    cookies.insert(k, v);
                                }
                            }
                        }
                    }

                    let mut retry_headers = HashMap::new();
                    for (name, value) in retry_resp.headers().iter() {
                        if let Ok(v) = value.to_str() {
                            retry_headers.insert(name.to_string(), v.to_string());
                        }
                    }

                    let retry_body = retry_resp.text().await.unwrap_or_default();

                    return Ok(ProxyResponse {
                        status: retry_status,
                        headers: retry_headers,
                        body: retry_body,
                    });
                }
            }
            Err(e) => {
                println!("[IPC] Token refresh failed: {}", e);
            }
        }
    }

    // Store cookies from response
    for (name, value) in resp.headers().iter() {
        if name.as_str().to_lowercase() == "set-cookie" {
            if let Ok(cookie_str) = value.to_str() {
                if let Some((k, v)) = parse_cookie(cookie_str) {
                    println!("[IPC] Storing cookie: {}", k);
                    let mut cookies = state.cookies.write().await;
                    cookies.insert(k, v);
                }
            }
        }
    }

    // Collect response headers
    let mut resp_headers = HashMap::new();
    for (name, value) in resp.headers().iter() {
        if let Ok(v) = value.to_str() {
            resp_headers.insert(name.to_string(), v.to_string());
        }
    }

    // Get response body
    let body = resp.text().await.unwrap_or_default();

    Ok(ProxyResponse {
        status,
        headers: resp_headers,
        body,
    })
}

/// Login with username and password
#[tauri::command]
async fn login(
    state: tauri::State<'_, Arc<AppState>>,
    username: String,
    password: String,
) -> Result<AuthSession, String> {
    state.auth.login(&username, &password).await.map_err(|e| {
        match e {
            AuthError::TwoFactorRequired => "2FA_REQUIRED".to_string(),
            AuthError::HumanVerificationRequired => "HUMAN_VERIFICATION_REQUIRED".to_string(),
            _ => format!("{}", e),
        }
    })
}

/// Submit 2FA TOTP code
#[tauri::command]
async fn submit_2fa(
    state: tauri::State<'_, Arc<AppState>>,
    code: String,
) -> Result<AuthSession, String> {
    state.auth.submit_2fa(&code).await.map_err(|e| format!("{}", e))
}

/// Check if authenticated
#[tauri::command]
async fn is_authenticated(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<bool, String> {
    Ok(state.auth.get_session().await.is_some())
}

/// Get current auth session
#[tauri::command]
async fn get_auth_session(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<Option<AuthSession>, String> {
    Ok(state.auth.get_session().await)
}

/// Logout
#[tauri::command]
async fn logout(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<(), String> {
    state.auth.logout().await.map_err(|e| format!("{}", e))
}

#[tauri::command]
async fn show_notification(title: String, body: String) {
    println!("Notification: {} - {}", title, body);
}

#[tauri::command]
async fn open_file_dialog() -> Result<Option<PathBuf>, String> {
    Ok(None)
}

#[tauri::command]
async fn get_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[tauri::command]
async fn check_for_updates() -> Result<bool, String> {
    Ok(false)
}

fn main() {
    std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");

    // Create shared state
    let state = Arc::new(AppState {
        client: Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("Failed to create HTTP client"),
        auth: AuthManager::new(PROTON_API_BASE),
        cookies: RwLock::new(HashMap::new()),
    });

    tauri::Builder::default()
        .manage(state)
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            // Fetch interceptor script - runs BEFORE any page JavaScript
            let init_script = r#"
// Immediately override fetch before any other JS runs
(function() {
    'use strict';

    console.log('[Tauri] Initializing fetch interceptor...');

    const originalFetch = window.fetch;
    const PROXY_PATTERNS = ['/api/', 'mail.proton.me', 'drive.proton.me', 'account.proton.me'];

    window.fetch = async function(input, init = {}) {
        let url = typeof input === 'string' ? input : (input.url || String(input));

        // Check if this should be proxied
        const shouldProxy = PROXY_PATTERNS.some(p => url.includes(p));

        if (!shouldProxy) {
            return originalFetch.call(window, input, init);
        }

        console.log('[Tauri Proxy]', init.method || 'GET', url);

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
            if (typeof init.body === 'string') {
                body = init.body;
            } else if (init.body instanceof FormData) {
                const obj = {};
                init.body.forEach((v, k) => obj[k] = v);
                body = JSON.stringify(obj);
                headers['content-type'] = 'application/json';
            } else if (init.body instanceof ArrayBuffer || init.body instanceof Uint8Array) {
                // Handle binary data - convert to base64
                const bytes = new Uint8Array(init.body);
                body = btoa(String.fromCharCode.apply(null, bytes));
                headers['x-tauri-binary'] = 'true';
            } else {
                body = JSON.stringify(init.body);
            }
        }

        try {
            const response = await window.__TAURI__.core.invoke('proxy_request', {
                request: { method, url, headers, body }
            });

            console.log('[Tauri Proxy] Response:', response.status, url);

            // Build response headers
            const respHeaders = new Headers();
            for (const [k, v] of Object.entries(response.headers || {})) {
                try { respHeaders.set(k, v); } catch(e) {}
            }

            return new Response(response.body, {
                status: response.status,
                statusText: response.status === 200 ? 'OK' : '',
                headers: respHeaders
            });
        } catch (err) {
            console.error('[Tauri Proxy] Error:', err);
            throw new TypeError('Network request failed: ' + err);
        }
    };

    // Also patch XMLHttpRequest for older code paths
    const OriginalXHR = window.XMLHttpRequest;
    window.XMLHttpRequest = function() {
        const xhr = new OriginalXHR();
        const originalOpen = xhr.open;
        const originalSend = xhr.send;
        let method = 'GET', url = '', headers = {};

        xhr.open = function(m, u, ...args) {
            method = m;
            url = u;
            return originalOpen.call(this, m, u, ...args);
        };

        const originalSetHeader = xhr.setRequestHeader;
        xhr.setRequestHeader = function(k, v) {
            headers[k] = v;
            return originalSetHeader.call(this, k, v);
        };

        xhr.send = function(body) {
            const shouldProxy = PROXY_PATTERNS.some(p => url.includes(p));

            if (!shouldProxy) {
                return originalSend.call(this, body);
            }

            console.log('[Tauri XHR]', method, url);

            window.__TAURI__.core.invoke('proxy_request', {
                request: { method, url, headers, body: body || null }
            }).then(response => {
                Object.defineProperty(xhr, 'status', { value: response.status, writable: false });
                Object.defineProperty(xhr, 'statusText', { value: 'OK', writable: false });
                Object.defineProperty(xhr, 'responseText', { value: response.body, writable: false });
                Object.defineProperty(xhr, 'response', { value: response.body, writable: false });
                Object.defineProperty(xhr, 'readyState', { value: 4, writable: false });

                xhr.dispatchEvent(new Event('readystatechange'));
                xhr.dispatchEvent(new Event('load'));
                xhr.dispatchEvent(new Event('loadend'));
            }).catch(err => {
                console.error('[Tauri XHR] Error:', err);
                xhr.dispatchEvent(new Event('error'));
            });
        };

        return xhr;
    };

    // Expose auth commands to frontend
    window.__PROTON_AUTH__ = {
        login: (username, password) => window.__TAURI__.core.invoke('login', { username, password }),
        submit2FA: (code) => window.__TAURI__.core.invoke('submit_2fa', { code }),
        isAuthenticated: () => window.__TAURI__.core.invoke('is_authenticated'),
        getSession: () => window.__TAURI__.core.invoke('get_auth_session'),
        logout: () => window.__TAURI__.core.invoke('logout')
    };

    window.__TAURI_FETCH_INJECTED__ = true;
    console.log('[Tauri] Fetch interceptor installed successfully');
})();
"#;

            // Create window with initialization script that runs before page JS
            let _window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                .title("Proton Drive")
                .inner_size(1200.0, 800.0)
                .min_inner_size(800.0, 600.0)
                .initialization_script(init_script)
                .build()?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            proxy_request,
            login,
            submit_2fa,
            is_authenticated,
            get_auth_session,
            logout,
            show_notification,
            open_file_dialog,
            get_app_version,
            check_for_updates,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
