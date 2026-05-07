# Agent Instructions

This repository builds one Tauri 2.0 Linux desktop client across AUR, AppImage, Flatpak, Snap, deb, and rpm. Keep core runtime behavior shared across every package format.

## Engineering Rules

- Do not make package-specific app code changes. Package differences belong only in workflows, install steps, build scripts, or packaging manifests.
- Keep local and CI WebClients handling equivalent: local scripts use an existing `WebClients/`; CI workflows clone a fresh copy.
- Use `patches/common/` for WebClients patches. Do not use `patches/webclients/`.
- Mirror WebClients build-script changes into GitHub Actions workflows.
- Prefer Tauri 2.0 conventions and Linux packaging compatibility over one-off fixes.
- Preserve zero-trust behavior: Proton's frontend handles auth/encryption; Rust proxies API traffic and handles desktop integration.

## Current Release State

- Version: `1.1.4`
- Validated: Fedora/RPM launch, login, CAPTCHA, 2FA, app selection, and Drive load.
- Working package targets: AUR, AppImage, RPM, DEB.
- Beta package targets: Flatpak, Snap.

## Docs

- Release notes: `CHANGELOG.md`
- Architecture and troubleshooting: `README.md`
- Debug history: `docs/debugging/worker-login-sri.md`
