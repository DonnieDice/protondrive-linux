/// Returns a local Drive URL when an SSO flow lands on an unsupported Proton app.
pub fn unsupported_app_redirect_url(url: &tauri::Url) -> Option<String> {
    let host = url.host_str()?;
    if !is_unsupported_proton_app_host(host)
        || url.path().starts_with("/api/")
        || url.path().starts_with("/captcha/")
    {
        return None;
    }

    Some(format!(
        "tauri://localhost{}",
        drive_root_for_user_path(url.path())
    ))
}

/// Returns a local Drive URL when the account app finishes SSO and lands on a
/// user-scoped Drive route.
pub fn account_login_complete_redirect_url(url: &tauri::Url) -> Option<String> {
    let path = url.path();
    let account_path = path.strip_prefix("/account").unwrap_or(path);

    if !is_account_login_complete_host(url.host_str())
        && !(is_local_app_host(url.host_str()) && path.starts_with("/account/u/"))
    {
        return None;
    }

    if !account_path.starts_with("/u/") || !account_path.contains("/drive") {
        return None;
    }

    Some(format!(
        "tauri://localhost{}",
        drive_root_for_user_path(account_path)
    ))
}

fn is_unsupported_proton_app_host(host: &str) -> bool {
    matches!(
        host,
        "calendar.proton.me"
            | "contacts.proton.me"
            | "docs.proton.me"
            | "mail.proton.me"
            | "pass.proton.me"
            | "wallet.proton.me"
            | "vpn.proton.me"
    )
}

fn is_account_login_complete_host(host: Option<&str>) -> bool {
    matches!(host, Some("account.proton.me") | Some("account.localhost"))
}

fn is_local_app_host(host: Option<&str>) -> bool {
    matches!(host, Some("localhost") | Some("tauri.localhost"))
}

fn drive_root_for_user_path(path: &str) -> String {
    if let Some(rest) = path.strip_prefix("/u/") {
        let user_id = rest.split('/').next().unwrap_or_default();
        if !user_id.is_empty() {
            return format!("/u/{}/", user_id);
        }
    }
    "/".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redirects_unsupported_app_to_user_scoped_drive_root() {
        let url = tauri::Url::parse("https://mail.proton.me/u/7/mail/inbox").unwrap();
        assert_eq!(
            unsupported_app_redirect_url(&url).as_deref(),
            Some("tauri://localhost/u/7/")
        );
    }

    #[test]
    fn skips_proton_api_and_captcha_paths() {
        let api_url = tauri::Url::parse("https://mail.proton.me/api/core/v4/users").unwrap();
        let captcha_url = tauri::Url::parse("https://mail.proton.me/captcha/token").unwrap();

        assert_eq!(unsupported_app_redirect_url(&api_url), None);
        assert_eq!(unsupported_app_redirect_url(&captcha_url), None);
    }

    #[test]
    fn ignores_supported_drive_host() {
        let url = tauri::Url::parse("https://drive.proton.me/u/7/").unwrap();
        assert_eq!(unsupported_app_redirect_url(&url), None);
    }

    #[test]
    fn redirects_account_proton_drive_handoff_to_local_drive_root() {
        let url = tauri::Url::parse("https://account.proton.me/u/7/drive/account").unwrap();
        assert_eq!(
            account_login_complete_redirect_url(&url).as_deref(),
            Some("tauri://localhost/u/7/")
        );
    }

    #[test]
    fn redirects_local_account_drive_handoff_to_local_drive_root() {
        let url = tauri::Url::parse("tauri://localhost/account/u/7/drive/account").unwrap();
        assert_eq!(
            account_login_complete_redirect_url(&url).as_deref(),
            Some("tauri://localhost/u/7/")
        );
    }

    #[test]
    fn ignores_incomplete_account_routes() {
        let url = tauri::Url::parse("tauri://localhost/account/login").unwrap();
        assert_eq!(account_login_complete_redirect_url(&url), None);
    }
}
