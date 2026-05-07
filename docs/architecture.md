# Architecture

Proton Drive Linux is a Tauri 2 desktop wrapper around Proton's WebClients Drive application.

The application has three main layers:

1. `WebClients/applications/drive/dist` contains the compiled Proton Drive web app.
2. `src-tauri/src/main.rs` creates the native Linux window and injects desktop-specific JavaScript.
3. Tauri bundles the Rust binary, web assets, desktop metadata, icons, and Linux package metadata.

## Runtime Flow

At startup, `main.rs`:

- Sets WebKitGTK environment variables to reduce GPU/EGL issues.
- Creates a shared `reqwest::Client` with cookie storage.
- Registers Tauri plugins for shell, dialog, and notifications.
- Builds a `main` webview window from `tauri://localhost/index.html`.
- Injects an initialization script before the web app runs.
- Registers navigation and download handlers.
- Registers Tauri commands used by the injected script.

The compiled frontend comes from:

```text
WebClients/applications/drive/dist
```

That path is configured in `src-tauri/tauri.conf.json` as:

```json
"frontendDist": "../WebClients/applications/drive/dist"
```

## Embedded WebClients Apps

The build process compiles more than the Drive app:

- `proton-drive` provides the main file UI.
- `proton-account` is copied into `drive/dist/account` for login and SSO.
- `proton-verify` is copied into `drive/dist/verify` for CAPTCHA and human verification.

After copying, build scripts rewrite nested asset paths and remove integrity/crossorigin attributes that would no longer match after relocation.

## Request Proxy

The embedded web app cannot call Proton APIs directly in all desktop contexts. The injected script intercepts API `fetch` and `XMLHttpRequest` calls and forwards them to the Rust command:

```rust
proxy_request
```

`proxy_request` rewrites local/Tauri API URLs to Proton API URLs, forwards request headers and body, stores cookies through the shared `reqwest` cookie jar, and returns a serialized response back to JavaScript.

The current proxy base is:

```rust
const PROTON_API_BASE: &str = "https://mail.proton.me";
```

## Navigation Rewrites

The Tauri navigation handler keeps web auth flows inside the local desktop app:

- `/login` is rewritten to `tauri://localhost/account/`.
- `account.proton.me` is rewritten to the local Account app.
- `drive.proton.me` is rewritten back to the local Drive app.
- `account.localhost` is treated as a completed login redirect and sends the user back to Drive.
- hCaptcha and Proton verify domains are allowed during human verification.
- direct `/api/` navigations are blocked because API calls should use the proxy.

## Downloads

The app handles downloads in two ways:

- Tauri's native `on_download` hook sets regular download destinations under `~/Downloads`.
- The injected script tracks `blob:` URLs created by the web app, captures filenames from anchor `download` attributes, reads blob bytes, and invokes:

```rust
save_download
```

`save_download` writes files to the user's Downloads directory, creating it if needed.

## Worker Compatibility

WebKitGTK worker support differs by package format and distribution. The injected script decides whether to leave Workers native or disable them based on the compile-time `DISTRO_TYPE` value:

- `appimage` and `aur` use native Workers.
- `deb`, `rpm`, `flatpak`, `snap`, and unset values disable Workers so Proton WebClients can use main-thread crypto fallback.

The shared patch in `patches/common/fix-tauri-worker-protocol.patch` also supports this compatibility work.

## Authentication Code Note

`src-tauri/src/auth.rs` contains an experimental Rust SRP authentication manager. It is not imported by `main.rs`, and `Cargo.toml` does not currently include all dependencies it references. Treat it as unused design/work-in-progress unless wiring it into the app deliberately.

The working application path relies on the Proton WebClients login UI plus the JavaScript/Rust proxy and navigation handling described above.
