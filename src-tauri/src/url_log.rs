/// Returns a URL without query parameters or fragments for log output.
pub fn sanitize_url_for_log(url: &str) -> String {
    if let Ok(parsed) = tauri::Url::parse(url) {
        let host = parsed.host_str().unwrap_or("unknown");
        return format!("{}://{}{}", parsed.scheme(), host, parsed.path());
    }
    "<unparsed-url>".to_string()
}
