use std::path::{Path, PathBuf};

/// Returns the persistent WebView storage directory under the app data folder.
pub fn persistent_webview_data_dir(app_data_dir: PathBuf) -> PathBuf {
    app_data_dir.join("webview")
}

/// Ensures the persistent WebView storage directory exists.
pub fn ensure_webview_data_dir(dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)
}
