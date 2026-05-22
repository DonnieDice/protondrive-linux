use reqwest::cookie::{CookieStore, Jar};
use std::collections::BTreeMap;
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

/// Builds a request Cookie header from WebKit's persisted cookies plus the
/// in-process HTTP client's jar. Client-jar cookies win because they contain
/// the freshest auth state immediately after login/2FA responses.
pub fn combined_cookie_header(
    window: &WebviewWindow,
    client_cookie_jar: &Jar,
    url: &Url,
) -> Option<String> {
    if !supports_cookies(url) {
        return None;
    }

    let webview_header = webview_cookie_header(window, url);
    let client_header = client_cookie_jar
        .cookies(url)
        .and_then(|value| value.to_str().ok().map(str::to_owned));

    merge_cookie_headers(webview_header.as_deref(), client_header.as_deref())
}

fn merge_cookie_headers(
    webview_header: Option<&str>,
    client_header: Option<&str>,
) -> Option<String> {
    let mut merged = BTreeMap::new();

    for header in [webview_header, client_header].into_iter().flatten() {
        for (name, value) in cookie_pairs(header) {
            merged.insert(name.to_string(), value.to_string());
        }
    }

    if merged.is_empty() {
        return None;
    }

    Some(
        merged
            .into_iter()
            .map(|(name, value)| format!("{name}={value}"))
            .collect::<Vec<_>>()
            .join("; "),
    )
}

fn cookie_pairs(header: &str) -> impl Iterator<Item = (&str, &str)> {
    header.split(';').filter_map(|part| {
        let trimmed = part.trim();
        let (name, value) = trimmed.split_once('=')?;

        if name.is_empty() {
            return None;
        }

        Some((name, value))
    })
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merges_cookie_headers_with_client_values_taking_precedence() {
        assert_eq!(
            merge_cookie_headers(Some("UID=old; theme=dark"), Some("UID=new; AUTH=token"))
                .as_deref(),
            Some("AUTH=token; UID=new; theme=dark")
        );
    }

    #[test]
    fn ignores_empty_cookie_parts() {
        assert_eq!(
            merge_cookie_headers(Some(" ; one=1; =bad"), Some("two=2")).as_deref(),
            Some("one=1; two=2")
        );
    }
}
