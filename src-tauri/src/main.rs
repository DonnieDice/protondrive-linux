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

const PROXY_PORT: u16 = 9543;
const PROTON_API_BASE: &str = "https://mail.proton.me";

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
    // Use reqwest's built-in cookie store - handles all cookie management automatically
    let cookie_jar = Arc::new(reqwest::cookie::Jar::default());

    let client = Arc::new(
        Client::builder()
            .cookie_provider(Arc::clone(&cookie_jar))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("Failed to create HTTP client")
    );

    // API proxy
    let api_proxy = warp::any()
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

                    println!("[PROXY] {} {}", method.as_str(), url);

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
                            && name_str != "cookie"
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
                            println!("[PROXY] Response: {} for {}", status_code, path.as_str());

                            let resp_headers = resp.headers().clone();
                            let body_bytes = resp.bytes().await.unwrap_or_default();

                            let mut response = warp::http::Response::builder()
                                .status(status_code);

                            // Forward response headers (cookies are handled by reqwest's jar)
                            for (name, value) in resp_headers.iter() {
                                let name_str = name.as_str().to_lowercase();
                                if name_str != "transfer-encoding"
                                    && name_str != "content-encoding"
                                    && name_str != "set-cookie"
                                {
                                    if let Ok(v) = value.to_str() {
                                        response = response.header(name.as_str(), v);
                                    }
                                }
                            }

                            // CORS headers - use specific origin, not wildcard
                            response = response
                                .header("Access-Control-Allow-Origin", "tauri://localhost")
                                .header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
                                .header("Access-Control-Allow-Headers", "content-type, x-pm-appversion, x-pm-apiversion, x-pm-uid, authorization")
                                .header("Access-Control-Expose-Headers", "x-pm-uid, date");

                            Ok::<_, warp::Rejection>(response.body(body_bytes.to_vec()).unwrap())
                        }
                        Err(e) => {
                            eprintln!("[PROXY] Error: {}", e);
                            Ok(warp::http::Response::builder()
                                .status(502)
                                .header("Access-Control-Allow-Origin", "tauri://localhost")
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
                .header("Access-Control-Allow-Origin", "tauri://localhost")
                .header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
                .header("Access-Control-Allow-Headers", "content-type, x-pm-appversion, x-pm-apiversion, x-pm-uid, authorization")
                .header("Access-Control-Max-Age", "86400")
                .body(vec![])
                .unwrap()
        });

    let routes = cors_preflight.or(api_proxy);
    let addr: SocketAddr = ([127, 0, 0, 1], PROXY_PORT).into();

    println!("🚀 API proxy on http://{}", addr);
    println!("   → {}", PROTON_API_BASE);
    warp::serve(routes).run(addr).await;
}

fn main() {
    std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");

    std::thread::spawn(|| {
        let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
        rt.block_on(start_proxy_server());
    });

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
