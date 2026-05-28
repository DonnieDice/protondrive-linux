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

    apply_default_cookie_scope(&mut cookie, url);

    let cookie_name = cookie.name().to_string();
    let cookie_domain = cookie.domain().unwrap_or("<none>").to_string();
    let cookie_path = cookie.path().unwrap_or("<none>").to_string();

    let legacy_delete_cookies = legacy_blank_domain_delete_cookies(&cookie);
    if let Err(e) = window.set_cookie(cookie) {
        eprintln!(
            "[Cookie] failed to store {} from {}: {e}",
            cookie_name,
            sanitize_url_for_log(url.as_str())
        );
    } else {
        println!(
            "[Cookie] stored name={} domain={} path={} source={}",
            cookie_name,
            cookie_domain,
            cookie_path,
            sanitize_url_for_log(url.as_str())
        );

        for legacy_cookie in legacy_delete_cookies {
            let legacy_name = legacy_cookie.name().to_string();
            let legacy_domain = legacy_cookie.domain().unwrap_or("<none>").to_string();
            let legacy_path = legacy_cookie.path().unwrap_or("<none>").to_string();
            match window.delete_cookie(legacy_cookie) {
                Ok(()) => println!(
                    "[Cookie] deleted legacy name={} domain={} path={}",
                    legacy_name, legacy_domain, legacy_path
                ),
                Err(e) => eprintln!(
                    "[Cookie] failed to delete legacy {} domain={} path={}: {e}",
                    legacy_name, legacy_domain, legacy_path
                ),
            }
        }
    }
}

fn supports_cookies(url: &Url) -> bool {
    url.scheme() == "http" || url.scheme() == "https"
}

fn apply_default_cookie_scope(cookie: &mut Cookie<'static>, url: &Url) {
    if cookie.path().is_none() {
        cookie.set_path(default_cookie_path(url));
    }

    // Keep-me-signed-in depends on WebKit persisting host-only Proton auth
    // cookies across app restarts. Tauri's set_cookie API does not receive the
    // response URL separately, so a Set-Cookie without Domain must be scoped to
    // the response host here or it is persisted with no usable domain.
    if cookie
        .domain()
        .map(str::trim)
        .unwrap_or_default()
        .is_empty()
    {
        if let Some(host) = url.host_str() {
            cookie.set_domain(host.to_string());
        }
    }
}

fn legacy_blank_domain_delete_cookies(cookie: &Cookie<'static>) -> Vec<Cookie<'static>> {
    if !is_proton_auth_cookie(cookie.name()) {
        return Vec::new();
    }

    let Some(domain) = cookie.domain() else {
        return Vec::new();
    };
    if domain.trim().is_empty() || domain != "mail.proton.me" {
        return Vec::new();
    }

    let path = cookie.path().unwrap_or("/").to_string();
    let name = cookie.name().to_string();

    // Older builds persisted AUTH/REFRESH cookies with an empty domain, which
    // leaves stale #HttpOnly_ rows in WebKit's cookie file. Delete both the
    // explicit blank-domain and host-only forms when a correctly scoped cookie
    // is stored so restart auth cannot see ambiguous legacy state.
    vec![
        Cookie::build((name.clone(), ""))
            .domain("")
            .path(path.clone())
            .secure(true)
            .http_only(true)
            .build(),
        Cookie::build((name, ""))
            .path(path)
            .secure(true)
            .http_only(true)
            .build(),
    ]
}

fn is_proton_auth_cookie(name: &str) -> bool {
    name.starts_with("AUTH-") || name.starts_with("REFRESH-")
}

/// Computes the RFC-6265 §5.1.4 default-path for a Set-Cookie whose Path
/// attribute was omitted: the longest prefix of the request URI path ending
/// in a "/", otherwise "/".
fn default_cookie_path(url: &Url) -> String {
    let path = url.path();
    if !path.starts_with('/') {
        return "/".to_string();
    }
    match path.rfind('/') {
        Some(0) | None => "/".to_string(),
        Some(idx) => path[..idx].to_string(),
    }
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
    fn default_cookie_path_matches_rfc_6265() {
        let root = Url::parse("https://example.com/").unwrap();
        assert_eq!(default_cookie_path(&root), "/");

        let single = Url::parse("https://example.com/foo").unwrap();
        assert_eq!(default_cookie_path(&single), "/");

        let nested = Url::parse("https://example.com/foo/bar").unwrap();
        assert_eq!(default_cookie_path(&nested), "/foo");

        let trailing = Url::parse("https://example.com/foo/bar/").unwrap();
        assert_eq!(default_cookie_path(&trailing), "/foo/bar");
    }

    #[test]
    fn host_only_cookies_are_scoped_to_response_host_for_restart_persistence() {
        let url = Url::parse("https://mail.proton.me/api/auth/refresh").unwrap();
        let mut cookie = Cookie::parse("AUTH-uid=token; Path=/api/; Secure; HttpOnly")
            .unwrap()
            .into_owned();

        apply_default_cookie_scope(&mut cookie, &url);

        assert_eq!(cookie.domain(), Some("mail.proton.me"));
        assert_eq!(cookie.path(), Some("/api/"));
    }

    #[test]
    fn blank_domain_cookies_are_scoped_to_response_host_for_restart_persistence() {
        let url = Url::parse("https://mail.proton.me/api/auth/refresh").unwrap();
        let mut cookie = Cookie::parse("AUTH-uid=token; Domain=; Path=/api/; Secure; HttpOnly")
            .unwrap()
            .into_owned();

        apply_default_cookie_scope(&mut cookie, &url);

        assert_eq!(cookie.domain(), Some("mail.proton.me"));
        assert_eq!(cookie.path(), Some("/api/"));
    }

    #[test]
    fn scoped_auth_cookies_generate_legacy_blank_domain_deletes() {
        let cookie = Cookie::parse(
            "REFRESH-uid=token; Domain=mail.proton.me; Path=/api/auth/refresh; Secure; HttpOnly",
        )
        .unwrap()
        .into_owned();

        let deletes = legacy_blank_domain_delete_cookies(&cookie);

        assert_eq!(deletes.len(), 2);
        assert_eq!(deletes[0].name(), "REFRESH-uid");
        assert_eq!(deletes[0].domain(), Some(""));
        assert_eq!(deletes[0].path(), Some("/api/auth/refresh"));
        assert_eq!(deletes[1].domain(), None);
        assert_eq!(deletes[1].path(), Some("/api/auth/refresh"));
    }

    #[test]
    fn non_auth_cookies_do_not_generate_legacy_deletes() {
        let cookie = Cookie::parse("Tag=default; Domain=mail.proton.me; Path=/; Secure")
            .unwrap()
            .into_owned();

        assert!(legacy_blank_domain_delete_cookies(&cookie).is_empty());
    }

    #[test]
    fn explicit_cookie_domain_is_preserved() {
        let url = Url::parse("https://mail.proton.me/api/auth/refresh").unwrap();
        let mut cookie = Cookie::parse("Session-Id=value; Domain=proton.me; Path=/; Secure")
            .unwrap()
            .into_owned();

        apply_default_cookie_scope(&mut cookie, &url);

        assert_eq!(cookie.domain(), Some("proton.me"));
        assert_eq!(cookie.path(), Some("/"));
    }

    #[test]
    fn ignores_empty_cookie_parts() {
        assert_eq!(
            merge_cookie_headers(Some(" ; one=1; =bad"), Some("two=2")).as_deref(),
            Some("one=1; two=2")
        );
    }
}
