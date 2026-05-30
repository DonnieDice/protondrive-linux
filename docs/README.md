---
title: "Documentation"
created: 2025-11-30
updated: 2026-05-28
type: index
tags: [architecture]
sources: []
---
# Documentation

Project documentation lives here. The root `README.md` is kept as the GitHub landing page.

## Architecture & Core Systems

These pages document the internals of how the native client works:

- **[Architecture](ARCHITECTURE.md)** — Definitive component diagram, three-layer design, startup flow, directory structure, env vars
- **[Architecture (Summary)](architecture.md)** — High-level overview (legacy — see ARCHITECTURE.md for full details)
- **[Proxy System](proxy-system.md)** — Complete fetch/XHR interception, serial invoke chain, URL rewriting, cookie management, request body serialization, CAPTCHA-in-proxy detection
- **[WebView Integration](webview-integration.md)** — Complete WebView subsystem: IPC commands, cookie handling, init script injection, security model, platform compatibility
- **[Proton Navigation](proton-navigation.md)** — URL rewriting rules, SSO routing, CAPTCHA lifecycle, domain mapping, SPA dead-document recovery
- **[SSO & Authentication](sso-authentication.md)** — Login/2FA/CAPTCHA flow, session restoration, credential auto-restore, verification token injection
- **[Auth Module](auth-module.md)** — Session lifecycle, cookie management, logout flow, header injection
- **[Blob Downloads](blob-downloads.md)** — Multi-point download interception, blob tracking, filename capture, Rust save pipeline

## Sync System

- **[Sync System](sync-system.md)** — Dual-change detection (inotify + polling), suppression cache, remote apply, path validation, Tauri event bridge
- **[Live Sync Module](live-sync-module.md)** — Core engine: watcher/poller threads, suppression cache, event contract, polling constants
- **[Sync Database](sync-database.md)** — Full SQLite schema, item states, privacy hashing model, migrations, root scopes
- **[Sync DB Module](sync-db-module.md)** — AppState wiring, SyncKeyring decryption, debounce/persistence, Tauri command integration
- **[Two-Way Sync Notes](sync.md)** — Legacy overview (see Sync System for current details)

## Build & Packaging

- **[Build System](build-system.md)** — Cargo features, DISTRO_TYPE, platform matrix, worker handling, patch architecture
- **[Build & Packaging (Summary)](build-packaging.md)** — Two-part build, patch system, CI/CD pipeline, packaging formats, compatibility gates
- **[Packaging, Compatibility, And Release](packaging.md)** — AppImage, deb, rpm, AUR, snap packaging details
- **[New Build/Package Checklist](new-build-checklist.md)** — Step-by-step build verification guide
- **[CI Pipeline Reference](ci-pipeline-reference.md)** — CI job matrix, artifact naming, release workflow
- **[CI Authority & Mirroring](ci-authority-and-mirroring.md)** — CI authority model and mirror strategy
- **[CI/CD Roadmap](ci-cd-roadmap.md)** — Planned CI improvements
- **[Release Checklist](release-checklist.md)** — Release process checklist

## Configuration & Utilities

- **[Configuration Reference](configuration-reference.md)** — Every constant, env var, timeout, and file path — centralized reference
- **[URL Log & WebView Storage](url-log-webview-storage.md)** — URL sanitization for log safety, persistent data directory management

## Development & Contributing

- [Contributing Workflow](workflow.md)
- [Contributing Build & Packaging](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## Debugging & Operations

- [Worker Login SRI Debugging](debugging/worker-login-sri.md)
- [Login And Sync Regression Runbook](login-sync-regression-runbook.md)
