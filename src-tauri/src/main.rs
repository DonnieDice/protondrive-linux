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
use rust_embed::Embed;

const PROXY_PORT: u16 = 9543;
// Base URL without /api - frontend paths already include /api prefix
const PROTON_API_BASE: &str = "https://mail.proton.me";

// Embed the frontend dist files at compile time
#[derive(Embed)]
#[folder = "../WebClients/applications/drive/dist"]
struct FrontendAssets;

/// Fix Set-Cookie headers for localhost proxy
/// Removes Domain attribute so cookies are stored for localhost instead of proton.me
/// Removes Secure attribute since localhost uses HTTP
/// Changes SameSite=None to SameSite=Lax since we're not cross-site
fn fix_set_cookie_for_localhost(cookie: &str) -> String {
    cookie
        .split(';')
        .map(|part| part.trim())
        .filter(|part| {
            let lower = part.to_lowercase();
            // Remove Domain=... attribute (cookies should be for localhost)
            !lower.starts_with("domain=") &&
            // Remove Secure attribute (localhost is HTTP)
            lower != "secure" &&
            // Remove SameSite=None (not needed for same-origin localhost)
            !lower.starts_with("samesite=none")
        })
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

/// Serve embedded static files
fn serve_static_file(path: &str) -> Option<warp::http::Response<Vec<u8>>> {
    // Remove leading slash
    let file_path = path.trim_start_matches('/');

    // Try to get the file, or index.html for SPA routing
    let asset = FrontendAssets::get(file_path)
        .or_else(|| {
            // For SPA: if path doesn't look like a file, serve index.html
            if !file_path.contains('.') || file_path.is_empty() {
                FrontendAssets::get("index.html")
            } else {
                None
            }
        });

    asset.map(|content| {
        let mime = mime_guess::from_path(file_path).first_or_octet_stream();
        warp::http::Response::builder()
            .status(200)
            .header("Content-Type", mime.as_ref())
            .header("Cache-Control", "no-cache")
            .body(content.data.to_vec())
            .unwrap()
    })
}

async fn start_proxy_server() {
    let client = Arc::new(
        Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("Failed to create HTTP client")
    );

    // API proxy - only handles /api/* paths
    let api_proxy = warp::path("api")
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

                    println!("[API] {} {}", method.as_str(), url);

                    let reqwest_method = reqwest::Method::from_str(method.as_str())
                        .unwrap_or(reqwest::Method::GET);

                    let mut request = client.request(reqwest_method, &url);

                    // Forward relevant headers
                    for (name, value) in headers.iter() {
                        let name_str = name.as_str().to_lowercase();
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

                            let mut response = warp::http::Response::builder()
                                .status(status_code);

                            for (name, value) in resp_headers.iter() {
                                let name_str = name.as_str().to_lowercase();
                                if name_str != "transfer-encoding"
                                    && name_str != "content-encoding"
                                {
                                    if let Ok(v) = value.to_str() {
                                        if name_str == "set-cookie" {
                                            let fixed_cookie = fix_set_cookie_for_localhost(v);
                                            response = response.header(name.as_str(), fixed_cookie);
                                        } else {
                                            response = response.header(name.as_str(), v);
                                        }
                                    }
                                }
                            }

                            Ok::<_, warp::Rejection>(response.body(body_bytes.to_vec()).unwrap())
                        }
                        Err(e) => {
                            eprintln!("[API] Error: {}", e);
                            Ok(warp::http::Response::builder()
                                .status(502)
                                .body(format!("Proxy error: {}", e).into_bytes())
                                .unwrap())
                        }
                    }
                }
            }
        });

    // CORS preflight for API
    let cors_preflight = warp::path("api")
        .and(warp::options())
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

    // Static file server for everything else
    let static_files = warp::get()
        .and(warp::path::full())
        .map(|path: warp::path::FullPath| {
            serve_static_file(path.as_str()).unwrap_or_else(|| {
                // Fallback to index.html for SPA
                serve_static_file("index.html").unwrap_or_else(|| {
                    warp::http::Response::builder()
                        .status(404)
                        .body(b"Not Found".to_vec())
                        .unwrap()
                })
            })
        });

    // Order: CORS preflight -> API proxy -> static files
    let routes = cors_preflight.or(api_proxy).or(static_files);
    let addr: SocketAddr = ([127, 0, 0, 1], PROXY_PORT).into();

    println!("🚀 Server starting on http://{}", addr);
    println!("   Frontend: embedded static files");
    println!("   API proxy: {} -> {}", "/api/*", PROTON_API_BASE);
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