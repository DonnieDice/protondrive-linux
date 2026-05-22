use tauri::webview::Cookie;
use tauri::{Url, WebviewWindow};

use crate::url_log::sanitize_url_for_log;

/// Builds a request Cookie header from WebKit's native cookie manager.
pub fn webview_cookie_header(window: &WebviewWindow, url: &Url) -> Option<String> {
    if !supports_cookies(url) {
        return None;
    }

    let cookies = window
        .cookies_for_url(url.clone())
        .map_err(|e| {
            eprintln!(
                "[Cookie] failed to read WebKit cookies for {}: {e}",
                sanitize_url_for_log(url.as_str())
            );
        })
        .ok()?;

    let cookie_pairs: Vec<String> = cookies
        .into_iter()
        .map(|cookie| format!("{}={}", cookie.name(), cookie.value()))
        .collect();

    if cookie_pairs.is_empty() {
        None
    } else {
        Some(cookie_pairs.join("; "))
    }
}

/// Stores a Set-Cookie response header in WebKit's native cookie manager.
pub fn store_webview_cookie(window: &WebviewWindow, url: &Url, set_cookie: &str) {
    if !supports_cookies(url) {
        return;
    }

    let mut cookie = match Cookie::parse(set_cookie.to_string()) {
        Ok(cookie) => cookie.into_owned(),
        Err(e) => {
            eprintln!(
                "[Cookie] failed to parse Set-Cookie from {}: {e}",
                sanitize_url_for_log(url.as_str())
            );
            return;
        }
    };

    if cookie.domain().is_none() {
        if let Some(host) = url.host_str() {
            cookie.set_domain(host.to_string());
        }
    }

    if cookie.path().is_none() {
        cookie.set_path("/");
    }

    let cookie_name = cookie.name().to_string();
    if let Err(e) = window.set_cookie(cookie) {
        eprintln!(
            "[Cookie] failed to store {} from {}: {e}",
            cookie_name,
            sanitize_url_for_log(url.as_str())
        );
    }
}

fn supports_cookies(url: &Url) -> bool {
    url.scheme() == "http" || url.scheme() == "https"
}
