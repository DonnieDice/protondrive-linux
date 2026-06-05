# Requirements And Pipeline Baseline

This page translates the public Proton Drive/Tauri research baseline into the
current `protondrive-linux` implementation. It is intentionally repo-specific:
it distinguishes the generic "trusted web shell" pattern from what this project
actually ships today.

## Baseline Constraint: Proton Owns Auth, Crypto, And Drive Semantics

Proton Drive remains the source of truth for account login, two-factor
authentication, CAPTCHA/human verification, encryption, and Drive file semantics.
The app must not replace Proton's cryptographic model with a local clone or a
third-party protocol shim.

Current project stance:

- The app is an unofficial Linux desktop client and must keep that disclaimer in
  user-facing docs and release surfaces.
- Proton's Drive SDKs are not treated as production integration surfaces for this
  project because standalone third-party auth support is not available.
- Reverse-engineered API integrations such as rclone/Proton-API-Bridge are not
  part of the current default architecture. If added later, they must be opt-in,
  documented separately, and store secrets through that tool's own secure config
  path rather than through this Tauri app.
- Native code may provide shell features, download handling, local file access,
  package integration, and sync-bridge primitives, but the web frontend remains
  responsible for Proton Drive upload/download semantics.

## Actual Architecture In This Repository

The research baseline describes a minimal Tauri shell that directly loads the
hosted Proton Drive SPA. This repository is more involved:

| Area | Minimal research baseline | Current repo behavior |
|------|---------------------------|-----------------------|
| Web app source | Load `https://drive.proton.me` in the WebView | Build ProtonMail/WebClients locally via `scripts/build-webclients.sh`; Tauri `frontendDist` points at `../WebClients/applications/drive/dist` in `src-tauri/tauri.conf.json`. |
| Startup URL | Hosted Drive URL | `WebviewWindowBuilder` starts `WebviewUrl::App("index.html")` in `src-tauri/src/main.rs`. |
| Proton navigation | Let hosted pages navigate normally | Navigation handler rewrites `/login`, `account.proton.me`, and `drive.proton.me` routes back into the local `tauri://localhost` app. |
| API calls | Browser/network stack talks to Proton directly | Injected initialization script wraps `fetch`/XHR API traffic and forwards it through the Rust `proxy_request` command. |
| Authentication | Hosted web app flow | Local Account/Verify WebClients routes plus Rust navigation guards handle login, 2FA, CAPTCHA completion tokens, and post-login Drive handoff. |
| Downloads | Browser default handling | Rust download handlers save standard and blob downloads into `~/Downloads`. |
| Sync | Not included, or future SDK/rclone | Experimental native sync bridge exists through Tauri commands and Rust filesystem watchers. |

The important requirement is therefore not merely "wrap the official URL". The
project requirement is: **ship a locally packaged Proton WebClients Drive shell
that preserves Proton-owned auth/crypto semantics while adding Linux-native
shell, packaging, and sync-bridge capabilities.**

## Functional Requirements

### Required user-visible behavior

- Launch a native Tauri/WebKitGTK desktop window branded as Proton Drive.
- Render the packaged Proton Drive web application from the Tauri app bundle.
- Support Proton login, CAPTCHA, 2FA, session continuation, and Drive handoff
  without persisting plaintext credentials.
- Route Proton Account/Verify/Drive navigation into local WebClients paths so
  the app stays inside the packaged shell.
- Proxy Proton API requests through the Rust backend where the injected web code
  requires same-origin behavior.
- Save Drive downloads to `~/Downloads` and handle blob-backed downloads.
- Expose a system-tray/background-desktop style app experience where the desktop
  environment and package format support it.
- Keep the client visibly unofficial in README, docs, package metadata, release
  notes, and store submissions.

### Current native sync bridge requirements

The sync bridge is experimental but implemented enough to have hard safety
requirements:

- A sync root must be under `$HOME`.
- Path traversal and symlink traversal must be rejected.
- Local file events are emitted to the frontend; the frontend owns remote upload
  semantics.
- Remote changes are applied only through validated relative paths.
- The suppression cache prevents watcher ping-pong after remote writes.
- Sync commands must be callable only from trusted Tauri origins.
- File reads crossing the bridge must obey the configured maximum file size.

### Explicit non-requirements today

- Do not require a Proton Drive SDK integration for the default app path.
- Do not require rclone or Proton-API-Bridge for default login, browsing, or
  downloads.
- Do not build a standalone Proton API client unless Proton exposes supported
  third-party auth and Drive APIs or the feature is explicitly scoped as
  experimental.
- Do not claim "all Linux" support. The accurate claim is release-gated
  mainstream `x86_64` Linux coverage through the package formats and distro
  matrix documented in [Packaging, Compatibility, And Release](../build-packaging/packaging.md).

## Packaging Requirements

Tauri/WebKitGTK creates two independent package compatibility gates:

1. **libc baseline** — glibc for DEB/RPM/AppImage/AUR/Snap/Flatpak targets, musl
   for Alpine APK targets.
2. **WebKitGTK availability** — native packages need WebKitGTK 4.1/GTK 3 from the
   target distro or package runtime; Flatpak and Snap satisfy this through their
   runtimes/snaps.

Release-gated package families currently include:

- AppImage for the portable glibc baseline.
- DEB for Debian and Ubuntu release targets.
- RPM for Fedora, EL10/RHEL-family, and openSUSE Tumbleweed.
- Flatpak for GNOME runtime targets.
- Snap for core24/core26 builds, with store publishing blocked until the Snap
  Store issue is resolved.
- AUR/Arch native package.
- APK/musl packages for Alpine targets.

The machine-readable target state lives in
[`packaging/compatibility-map.yml`](../../packaging/compatibility-map.yml), and
the human-readable support matrix lives in
[Packaging, Compatibility, And Release](../build-packaging/packaging.md).

## CI/CD Requirements

GitLab CI is the authoritative build and release system. GitHub Actions mirrors
selected behavior for GitHub contributors and manual package builds, but it is
not the release authority.

Required pipeline layers:

1. **Pre-flight tests** — login-routing regression, sync regression, formatting,
   clippy, and Rust unit tests.
2. **Package builds** — distro/package-specific build jobs for the full release
   matrix.
3. **Gate stage** — a fail-fast sentinel before remote VM transfer/install/test
   work.
4. **Transfer/install/vmtest chain** — copy artifacts to target VMs, install with
   the native package manager, and confirm the GUI actually appears under a
   compositor.
5. **Reports** — always-run deployment matrix, Robot Framework output, pytest
   output, screenshots, and Pages dashboard artifacts.
6. **Spec/release/publish stages** — generate package specs/source archives,
   upload release artifacts, and publish to external stores when their secrets
   and store-side prerequisites are valid.

The canonical CI details are documented in
[CI/CD Pipeline](../ci-cd/ci-pipeline.md).

## Testing Requirements

Testing must cover the desktop shell, the Rust backend, the WebClients routing
patches, and real package installation.

| Layer | Required coverage | Existing anchors |
|-------|-------------------|------------------|
| Rust backend | `cargo test`, `cargo fmt --check`, `cargo clippy`; proxy/navigation/sync command behavior | `.gitlab/workflows/tests.yml`, `.github/workflows/sanity.yml`, `src-tauri/src/*.rs` |
| Login/navigation regressions | Guard Account/Verify/Drive routing, CAPTCHA completion token handling, and post-2FA Drive handoff | `scripts/ci/regression/login-routing.sh`, `src-tauri/src/proton_navigation.rs`, `src-tauri/src/webview_cookies.rs` |
| Sync regressions | Ensure CI definitions and sync bridge expectations do not drift | `scripts/ci/regression/sync.sh`, `tests/robot/suites/functional/03_sync.robot` |
| GUI smoke | Prove that the installed app opens a visible WebKitGTK window, not only a live process | `scripts/ci/lib/gui-load-check.sh`, `scripts/ci/lib/ui-test-compositor.sh` |
| Install verification | Install each artifact with the target distro's native package manager | `scripts/ci/install/<distro>/install.sh` |
| Cross-distro runtime checks | Run VM-specific checks after package install | `scripts/ci/vmtest/<distro>/test.sh` |
| Documentation build | Ensure VitePress docs compile after doc/navigation edits | `npm run docs:build` |

## Decision Record: Hosted Shell Versus Packaged WebClients

The pasted research baseline is still valuable, but it describes the conservative
minimum viable product. This repository has already crossed into a packaged
WebClients architecture. That creates more maintenance burden, but it also gives
the Linux package pipeline deterministic frontend artifacts and allows targeted
patches for Account, Verify, Drive, SRI, workers, navigation, download handling,
and sync bridge integration.

Decision:

- Continue documenting and testing the packaged WebClients architecture as the
  current implementation.
- Keep the hosted-URL shell model as a fallback architectural reference, not as
  the active design.
- Revisit SDK/rclone integration only as a separate design proposal with explicit
  security, credential-storage, and support disclaimers.

## Troubleshooting

### Login succeeds but Drive stays on Account/Verify or freezes after 2FA

**Likely causes**

- Navigation rewrite drift between Account, Verify, and Drive routes.
- CAPTCHA completion inferred from an internal navigation instead of an explicit
  `hv_token`/`hv_type` return URL.
- WebKitGTK kept the Account document alive after a same-origin Drive handoff.

**Fix path**

1. Run `scripts/ci/regression/login-routing.sh`.
2. Inspect `src-tauri/src/proton_navigation.rs` and the navigation handler in
   `src-tauri/src/main.rs`.
3. Run Rust unit tests and the login Robot suite before releasing.

### Package builds but the installed app opens a blank window

**Likely causes**

- WebKitGTK runtime dependency mismatch for the target distro.
- Missing target-specific WebKitGTK environment patch.
- SRI/worker/local asset path drift in the WebClients patch.

**Fix path**

1. Confirm the target's compatibility state in `packaging/compatibility-map.yml`.
2. Check the matching `patches/<package>/<target>.patch`.
3. Run the matching install and vmtest scripts under `scripts/ci/`.
4. Review screenshots/OCR output from the report stage rather than trusting only
   process liveness.

### A package target exists as a patch but is not release-gated

**Likely causes**

- Workflow job, artifact upload, release `needs`, publish path, or smoke record
  is missing.

**Fix path**

Follow [New Package Checklist](../build-packaging/new-build-checklist.md), then
update both `docs/build-packaging/packaging.md` and
`packaging/compatibility-map.yml`.

## See Also

- [Architecture](./architecture.md) — high-level application architecture.
- [Build System](./build-system.md) — how WebClients and Tauri are assembled.
- [Proxy System](./proxy-system.md) — Rust-side API proxy behavior.
- [App Navigation](./proton-navigation.md) — Proton Account/Verify/Drive routing.
- [WebView Integration](../webview/webview-integration.md) — injected WebView
  bridge behavior.
- [Two-Way Sync Notes](../sync/sync.md) — native sync bridge scope and cautions.
- [Packaging, Compatibility, And Release](../build-packaging/packaging.md) —
  distro/package support matrix.
- [CI/CD Pipeline](../ci-cd/ci-pipeline.md) — authoritative CI and release flow.
