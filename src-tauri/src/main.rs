#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::path::PathBuf;
use std::net::SocketAddr;
use warp::Filter;
use reqwest::Client;
use std::sync::Arc;
use std::str::FromStr;

const PROXY_PORT: u16 = 9543;
const PROTON_API_BASE: &str = "https://mail.proton.me/api";

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
    let client = Arc::new(
        Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .cookie_store(true)
            .user_agent("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
            .build()
            .expect("Failed to create HTTP client")
    );

    // Proxy all requests to Proton API
    let proxy = warp::any()
        .and(warp::method())
        .and(warp::path::full())
        .and(warp::header::headers_cloned())
        .and(warp::body::bytes())
        .and(warp::query::raw().or(warp::any().map(String::new)).unify())
        .and_then({
            let client = Arc::clone(&client);
            move |method: warp::http::Method,
                  path: warp::path::FullPath,
                  headers: warp::http::HeaderMap,
                  body: bytes::Bytes,
                  query: String| {
                let client = Arc::clone(&client);
                async move {
                    let url = if query.is_empty() {
                        format!("{}{}", PROTON_API_BASE, path.as_str())
                    } else {
                        format!("{}{}?{}", PROTON_API_BASE, path.as_str(), query)
                    };

                    // Log the request for debugging
                    println!("[PROXY] {} {}", method.as_str(), url);

                    // Convert warp::http::Method to reqwest::Method
                    let reqwest_method = reqwest::Method::from_str(method.as_str())
                        .unwrap_or(reqwest::Method::GET);

                    let mut request = client.request(reqwest_method, &url);

                    // Forward relevant headers
                    for (name, value) in headers.iter() {
                        let name_str = name.as_str().to_lowercase();
                        // Skip hop-by-hop headers and host
                        if name_str != "host"
                            && name_str != "connection"
                            && name_str != "keep-alive"
                            && name_str != "transfer-encoding"
                            && name_str != "te"
                            && name_str != "trailer"
                            && name_str != "upgrade"
                            && name_str != "origin"
                            && name_str != "referer"
                        {
                            if let Ok(v) = value.to_str() {
                                request = request.header(name.as_str(), v);
                            }
                        }
                    }

                    // Add Proton-specific headers if not already set
                    request = request.header("x-pm-appversion", "web-drive@5.0.0")
                        .header("x-pm-apiversion", "3")
                        .header("Origin", "https://drive.proton.me")
                        .header("Referer", "https://drive.proton.me/");

                    // Set body for methods that support it
                    if method != warp::http::Method::GET && method != warp::http::Method::HEAD {
                        request = request.body(body.to_vec());
                    }

                    match request.send().await {
                        Ok(resp) => {
                            let status_code = resp.status().as_u16();
                            println!("[PROXY] Response: {}", status_code);
                            let resp_headers = resp.headers().clone();
                            let body_bytes = resp.bytes().await.unwrap_or_default();

                            let mut response = warp::http::Response::builder()
                                .status(status_code);

                            // Forward response headers
                            for (name, value) in resp_headers.iter() {
                                let name_str = name.as_str().to_lowercase();
                                if name_str != "transfer-encoding"
                                    && name_str != "content-encoding"
                                {
                                    if let Ok(v) = value.to_str() {
                                        response = response.header(name.as_str(), v);
                                    }
                                }
                            }

                            // Add CORS headers
                            response = response
                                .header("Access-Control-Allow-Origin", "*")
                                .header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
                                .header("Access-Control-Allow-Headers", "*")
                                .header("Access-Control-Expose-Headers", "*");

                            Ok::<_, warp::Rejection>(response.body(body_bytes.to_vec()).unwrap())
                        }
                        Err(e) => {
                            eprintln!("Proxy error: {}", e);
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

    // Handle CORS preflight
    let cors_preflight = warp::options()
        .map(|| {
            warp::http::Response::builder()
                .status(204)
                .header("Access-Control-Allow-Origin", "*")
                .header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
                .header("Access-Control-Allow-Headers", "*")
                .header("Access-Control-Max-Age", "86400")
                .body(vec![])
                .unwrap()
        });

    let routes = cors_preflight.or(proxy);
    let addr: SocketAddr = ([127, 0, 0, 1], PROXY_PORT).into();

    println!("Starting API proxy on http://{}", addr);
    println!("Proxying requests to: {}", PROTON_API_BASE);
    warp::serve(routes).run(addr).await;
}

fn main() {
    // Fix WebKitGTK EGL/GPU issues on various Linux configurations
    // These must be set before any GTK/WebKit initialization
    // Required for AMD, Intel, and some NVIDIA GPU configurations
    // Note: These are also set in wrapper scripts for AppImage/Flatpak/Snap,
    // but we set them here as well for deb/rpm installs that run the binary directly
    std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");

    // Start proxy server in background thread
    std::thread::spawn(|| {
        let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
        rt.block_on(async {
            println!("🚀 Starting Proton Drive API proxy...");
            start_proxy_server().await;
        });
    });

    // Give proxy time to start and bind to port
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