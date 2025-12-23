#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::path::PathBuf;
use std::net::SocketAddr;
use std::sync::Arc;
use std::str::FromStr;
use warp::Filter;
use reqwest::Client;
use tokio::sync::RwLock;
use std::collections::HashMap;

const PROXY_PORT: u16 = 9543;
const PROTON_API_BASE: &str = "https://mail.proton.me";

/// Server-side cookie storage - bypasses browser cookie restrictions entirely
type CookieJar = Arc<RwLock<HashMap<String, String>>>;

/// Extract cookie name and value from Set-Cookie header
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

async fn start_proxy_server() {
    // Server-side cookie jar - we manage cookies ourselves
    let cookies: CookieJar = Arc::new(RwLock::new(HashMap::new()));

    let client = Arc::new(
        Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("Failed to create HTTP client")
    );

    // API proxy with server-side cookie management
    let api_proxy = warp::any()
        .and(warp::method())
        .and(warp::path::full())
        .and(warp::header::headers_cloned())
        .and(warp::body::bytes())
        .and(warp::query::raw().or(warp::any().map(String::new)).unify())
        .and_then({
            let client = Arc::clone(&client);
            let cookies = Arc::clone(&cookies);
            move |method: warp::http::Method,
                  path: warp::path::FullPath,
                  headers: warp::http::HeaderMap,
                  body: bytes::Bytes,
                  query: String| {
                let client = Arc::clone(&client);
                let cookies = Arc::clone(&cookies);
                async move {
                    let url = if query.is_empty() {
                        format!("{}{}", PROTON_API_BASE, path.as_str())
                    } else {
                        format!("{}{}?{}", PROTON_API_BASE, path.as_str(), query)
                    };

                    println!("[API] {} {}", method.as_str(), url);

                    let reqwest_method = reqwest::Method::from_str(method.as_str())
                        .unwrap_or(reqwest::Method::GET);

                    let mut request = client.request(reqwest_method, &url);

                    // Forward relevant headers from browser
                    for (name, value) in headers.iter() {
                        let name_str = name.as_str().to_lowercase();
                        // Skip hop-by-hop headers, host, and cookie (we manage cookies ourselves)
                        if name_str != "host"
                            && name_str != "connection"
                            && name_str != "keep-alive"
                            && name_str != "transfer-encoding"
                            && name_str != "te"
                            && name_str != "trailer"
                            && name_str != "upgrade"
                            && name_str != "origin"
                            && name_str != "referer"
                            && name_str != "cookie"  // We add our own cookies
                        {
                            if let Ok(v) = value.to_str() {
                                request = request.header(name.as_str(), v);
                            }
                        }
                    }

                    // Add our server-side cookies
                    {
                        let jar = cookies.read().await;
                        if !jar.is_empty() {
                            let cookie_header = build_cookie_header(&jar);
                            println!("[API] Sending {} cookies", jar.len());
                            request = request.header("Cookie", cookie_header);
                        }
                    }

                    // Add Proton-specific headers
                    request = request
                        .header("x-pm-appversion", "web-drive@5.0.0")
                        .header("x-pm-apiversion", "3")
                        .header("Origin", "https://drive.proton.me")
                        .header("Referer", "https://drive.proton.me/");

                    if method != warp::http::Method::GET && method != warp::http::Method::HEAD {
                        request = request.body(body.to_vec());
                    }

                    match request.send().await {
                        Ok(resp) => {
                            let status_code = resp.status().as_u16();
                            println!("[API] Response: {}", status_code);
                            let resp_headers = resp.headers().clone();
                            let body_bytes = resp.bytes().await.unwrap_or_default();

                            // Store cookies server-side
                            for (name, value) in resp_headers.iter() {
                                if name.as_str().to_lowercase() == "set-cookie" {
                                    if let Ok(cookie_str) = value.to_str() {
                                        if let Some((k, v)) = parse_cookie(cookie_str) {
                                            println!("[API] Storing cookie: {}", k);
                                            let mut jar = cookies.write().await;
                                            jar.insert(k, v);
                                        }
                                    }
                                }
                            }

                            let mut response = warp::http::Response::builder()
                                .status(status_code);

                            // Forward response headers (except Set-Cookie - we handle those ourselves)
                            for (name, value) in resp_headers.iter() {
                                let name_str = name.as_str().to_lowercase();
                                if name_str != "transfer-encoding"
                                    && name_str != "content-encoding"
                                    && name_str != "set-cookie"  // Don't forward to browser
                                {
                                    if let Ok(v) = value.to_str() {
                                        response = response.header(name.as_str(), v);
                                    }
                                }
                            }

                            // Add CORS headers for browser
                            response = response
                                .header("Access-Control-Allow-Origin", "*")
                                .header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
                                .header("Access-Control-Allow-Headers", "*")
                                .header("Access-Control-Allow-Credentials", "true")
                                .header("Access-Control-Expose-Headers", "*");

                            Ok::<_, warp::Rejection>(response.body(body_bytes.to_vec()).unwrap())
                        }
                        Err(e) => {
                            eprintln!("[API] Error: {}", e);
                            Ok(warp::http::Response::builder()
                                .status(502)
                                .header("Access-Control-Allow-Origin", "*")
                                .body(format!("Proxy error: {}", e).into_bytes())
                                .unwrap())
                        }
                    }
                }
            }
        });

    // CORS preflight
    let cors_preflight = warp::options()
        .map(|| {
            warp::http::Response::builder()
                .status(204)
                .header("Access-Control-Allow-Origin", "*")
                .header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
                .header("Access-Control-Allow-Headers", "*")
                .header("Access-Control-Allow-Credentials", "true")
                .header("Access-Control-Max-Age", "86400")
                .body(vec![])
                .unwrap()
        });

    let routes = cors_preflight.or(api_proxy);
    let addr: SocketAddr = ([127, 0, 0, 1], PROXY_PORT).into();

    println!("🚀 API proxy starting on http://{}", addr);
    println!("   Proxying to: {}", PROTON_API_BASE);
    println!("   Cookie management: server-side (bypasses browser restrictions)");
    warp::serve(routes).run(addr).await;
}

fn main() {
    // Fix WebKitGTK EGL/GPU issues
    std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");

    // Start proxy server in background
    std::thread::spawn(|| {
        let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
        rt.block_on(async {
            start_proxy_server().await;
        });
    });

    // Give proxy time to start
    std::thread::sleep(std::time::Duration::from_millis(500));

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![
            show_notification,
            open_file_dialog,
            get_app_version,
            check_for_updates,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
