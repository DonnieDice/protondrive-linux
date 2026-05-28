# Documentation

Project documentation lives here. The root `README.md` is kept as the GitHub landing page.

## Architecture & Core Systems

These pages document the internals of how the native client works:

- **[Architecture](architecture.md)** — High-level overview, component diagram, three-layer design, startup flow, directory structure
- **[Proxy System](proxy-system.md)** — Complete fetch/XHR interception, serial invoke chain, URL rewriting, cookie management, request body serialization, CAPTCHA-in-proxy detection
- **[SSO & Authentication](sso-authentication.md)** — Login/2FA/CAPTCHA flow, session restoration, URL rewriting, credential auto-restore, verification token injection
- **[Blob Downloads](blob-downloads.md)** — Multi-point download interception, blob tracking, filename capture, Rust save pipeline
- **[Sync System](sync-system.md)** — Dual-change detection (inotify + polling), suppression cache, remote apply, path validation, Tauri event bridge
- **[Sync Database](sync-database.md)** — Full SQLite schema, item states, privacy hashing model, migrations, root scopes
- **[WebView Configuration](webview-configuration.md)** — GPU/rendering workarounds, Worker polyfill, console bridge, error boundary, navigation handler, init script subsystems
- **[Build & Packaging](build-packaging.md)** — Two-part build, patch system, DISTRO_TYPE, CI/CD pipeline, packaging formats, compatibility gates

## Development

- [Contributing Workflow](workflow.md)
- [Contributing Build & Packaging](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## Packaging & Release

- [Packaging, Compatibility, And Release](packaging.md)
- [CI/CD Roadmap](ci-cd-roadmap.md)
- [Release Checklist](release-checklist.md)
- [New Build/Package Checklist](new-build-checklist.md)

## CI Authority

- [CI Authority & Mirroring](ci-authority-and-mirroring.md)

## Debugging

- [Worker Login SRI Debugging](debugging/worker-login-sri.md)

## Runtime

- [Login And Sync Regression Runbook](login-sync-regression-runbook.md)
- [Two-Way Sync Notes](sync.md) (legacy — see [Sync System](sync-system.md) for current details)
