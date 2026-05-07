# Changelog

## 1.1.3 - 2026-05-07

### Fixed

- Fixed Fedora/RPM launch flow through login, CAPTCHA, 2FA, app selection, and Drive load.
- Fixed WebClient chunk loading after login by building Drive, Account, and Verify with `--no-sri` and keeping nested Account/Verify chunk paths relative.
- Fixed Account app reload loops by blocking `/api/` document navigations that should be handled by the fetch proxy.
- Fixed CAPTCHA completion by allowing internal `about:blank` captcha navigations and only returning to Account after an explicit verification-token callback.
- Fixed CAPTCHA auth retry by preserving credentials temporarily, carrying the verification token back to the local Account app, and adding Proton human-verification headers to the retried auth request.
- Reduced noisy Tauri ACL errors from external captcha pages by only forwarding console logs to Rust on local `tauri://` pages.

### Verified

- Fedora local release binary launched with `WEBKIT_DISABLE_DMABUF_RENDERER=1` and `WEBKIT_DISABLE_COMPOSITING_MODE=1`.
- Login screen rendered without refresh loop.
- CAPTCHA completed, 2FA prompt appeared, app selection loaded, and Drive opened successfully.

### Repository Hygiene

- Moved long debugging notes to `docs/debugging/worker-login-sri.md`.
- Cleaned agent guidance files and ignored local agent state directories.
- Kept application lockfiles tracked for reproducible release builds.

## 1.1.2 - 2026-05-07

### Fixed

- Fixed WebKit worker startup failures affecting RPM/DEB builds on Fedora and Ubuntu.
- Added WebKitGTK rendering environment flags for AMD/Wayland startup stability.
