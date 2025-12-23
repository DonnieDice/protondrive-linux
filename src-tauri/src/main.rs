#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tauri::Manager;
use tokio::sync::RwLock;

const PROTON_API_BASE: &str = "https://mail.proton.me";

/// Shared HTTP client with cookie jar
struct AppState {
    client: Client,
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

    let mut req = state.client.request(method, &url);

    // Add stored cookies
    {
        let cookies = state.cookies.read().await;
        if !cookies.is_empty() {
            let cookie_header = build_cookie_header(&cookies);
            req = req.header("Cookie", cookie_header);
        }
    }

    // Forward headers from frontend (except cookie - we manage those)
    for (key, value) in &request.headers {
        let key_lower = key.to_lowercase();
        if key_lower != "cookie" && key_lower != "host" {
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
    if let Some(body) = request.body {
        req = req.body(body);
    }

    // Send request
    let resp = req.send().await.map_err(|e| format!("Request failed: {}", e))?;

    let status = resp.status().as_u16();
    println!("[IPC] Response: {}", status);

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

    // Create shared state with HTTP client
    let state = Arc::new(AppState {
        client: Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("Failed to create HTTP client"),
        cookies: RwLock::new(HashMap::new()),
    });

    tauri::Builder::default()
        .manage(state)
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            // Inject fetch interceptor into webview
            let window = app.get_webview_window("main").unwrap();

            // This script intercepts fetch() and routes through Tauri IPC
            let inject_script = r#"
(function() {
    if (window.__TAURI_FETCH_INJECTED__) return;
    window.__TAURI_FETCH_INJECTED__ = true;

    const originalFetch = window.fetch;
    const PROXY_PATTERNS = ['/api/', 'mail.proton.me', 'drive.proton.me', 'account.proton.me'];

    window.fetch = async function(input, init = {}) {
        let url = typeof input === 'string' ? input : input.url;

        // Check if this should be proxied
        const shouldProxy = PROXY_PATTERNS.some(p => url.includes(p));

        if (!shouldProxy) {
            return originalFetch.call(window, input, init);
        }

        // Extract request details
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
                // FormData needs special handling - convert to JSON if possible
                const obj = {};
                init.body.forEach((v, k) => obj[k] = v);
                body = JSON.stringify(obj);
                headers['content-type'] = 'application/json';
            } else {
                body = JSON.stringify(init.body);
            }
        }

        try {
            // Call Tauri IPC
            const response = await window.__TAURI__.core.invoke('proxy_request', {
                request: { method, url, headers, body }
            });

            // Construct Response object
            return new Response(response.body, {
                status: response.status,
                headers: response.headers
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
        let method, url, headers = {};

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

            // Route through Tauri
            window.__TAURI__.core.invoke('proxy_request', {
                request: { method, url, headers, body: body || null }
            }).then(response => {
                Object.defineProperty(xhr, 'status', { value: response.status });
                Object.defineProperty(xhr, 'responseText', { value: response.body });
                Object.defineProperty(xhr, 'response', { value: response.body });
                Object.defineProperty(xhr, 'readyState', { value: 4 });

                if (xhr.onreadystatechange) xhr.onreadystatechange();
                if (xhr.onload) xhr.onload();
            }).catch(err => {
                if (xhr.onerror) xhr.onerror(err);
            });
        };

        return xhr;
    };

    console.log('[Tauri] Fetch/XHR interceptor installed');
})();
"#;

            window.eval(inject_script).expect("Failed to inject fetch interceptor");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            proxy_request,
            show_notification,
            open_file_dialog,
            get_app_version,
            check_for_updates,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
