#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::path::PathBuf;

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

fn main() {
    // Fix WebKitGTK EGL/GPU issues on various Linux configurations
    // These must be set before any GTK/WebKit initialization
    // Required for AMD, Intel, and some NVIDIA GPU configurations
    std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");

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
