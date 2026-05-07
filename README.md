# Proton Drive Linux

Unofficial Linux desktop wrapper for Proton Drive, built with Tauri 2 and Rust.

This project packages Proton's open-source WebClients Drive app inside a native Linux desktop shell. The Rust/Tauri layer provides the application window, Linux packaging, download handling, WebKitGTK compatibility fixes, and a local request proxy so the embedded web client can talk to Proton APIs from the desktop runtime.

> This is not an official Proton product. It depends on Proton's public WebClients repository and can break when upstream WebClients or Proton web APIs change.

## Current Status

Version `1.1.2` is a working beta. Login, 2FA, CAPTCHA flow, file browsing, and downloads to `~/Downloads` are implemented. The project is Linux-focused and targets `x86_64` packages.

Known limitations:

- No native sync daemon or background file synchronization.
- The embedded Proton web app must be rebuilt from `ProtonMail/WebClients`.
- WebKitGTK behavior differs across distributions, so package-specific testing matters.
- `src-tauri/src/auth.rs` is experimental standalone SRP auth code and is not currently wired into the Tauri app.

## Documentation

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Build and Release](docs/build-and-release.md)
- [Packaging](docs/packaging.md)
- [Multi-Agent Coordination](docs/multi-agent-coordination.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Contributing](CONTRIBUTING.md)

## Repository Layout

```text
.
|-- src-tauri/                 Tauri 2 application shell and Rust code
|   |-- src/main.rs            Main app, proxy, navigation, downloads, init script
|   |-- src/auth.rs            Experimental, currently unused auth module
|   |-- tauri.conf.json        Tauri app and bundle configuration
|   `-- capabilities/          Tauri v2 permission capabilities
|-- scripts/                   Local build, setup, release, and packaging helpers
|-- patches/                   Patches applied to Proton WebClients
|-- .github/workflows/         CI builds and release automation
|-- aur/                       AUR package metadata
|-- snap/                      Snap packaging metadata
|-- package.json               Node scripts and Tauri CLI dependency
`-- Makefile                   Convenience wrapper around common commands
```

`WebClients/` is intentionally not committed in this repository. Local development expects you to create it beside these files. CI workflows clone it fresh.

## Prerequisites

Install these before building locally:

- Git
- Node.js 22 or current LTS
- Rust stable with Cargo
- Python 3
- A Linux environment with WebKitGTK 4.1 development packages
- Distribution build tools such as `build-essential`, `gcc`, `pkg-config`, and OpenSSL development headers

Debian/Ubuntu package baseline:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git curl pkg-config python3 libssl-dev \
  libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev \
  librsvg2-dev libsoup-3.0-dev
```

Fedora package baseline:

```bash
sudo dnf install -y \
  gcc gcc-c++ make git curl pkg-config python3 openssl-devel \
  webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel \
  librsvg2-devel libsoup3-devel
```

Arch package baseline:

```bash
sudo pacman -S --needed \
  base-devel git curl pkgconf python openssl webkit2gtk-4.1 gtk3 \
  libayatana-appindicator librsvg libsoup3
```

## Setup

Clone this repository:

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
```

Clone Proton WebClients into the expected local path:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Install the root Tauri CLI dependency:

```bash
npm install
```

The WebClients dependencies are installed by `npm run build:web`.

## Development

Build the embedded web client:

```bash
npm run build:web
```

Run the Tauri app in development mode:

```bash
npm run dev
```

The Tauri app reads frontend assets from:

```text
WebClients/applications/drive/dist
```

## Building Packages

Build the web client and Tauri Linux bundles:

```bash
npm run build
```

Build one package family:

```bash
npm run build:deb
npm run build:rpm
npm run build:appimage
```

Outputs are written under:

```text
src-tauri/target/release/bundle/
```

## Important Build Behavior

The local and CI flows are similar but not identical:

- Local builds use an existing `WebClients/` directory.
- CI builds clone `ProtonMail/WebClients` fresh.
- `scripts/fix_deps.py` modifies WebClients dependency metadata for public npm builds.
- `scripts/create_stubs.py` creates stubs for private Proton packages in CI.
- `patches/common/fix-tauri-worker-protocol.patch` adjusts WebClients behavior for Tauri/WebKitGTK.
- The Account and Verify apps are copied into `applications/drive/dist/account` and `applications/drive/dist/verify` so SSO and CAPTCHA can work inside the desktop wrapper.

When changing local build behavior, mirror the same behavior in GitHub Actions where relevant.

## Troubleshooting

Start with [docs/troubleshooting.md](docs/troubleshooting.md).

For WebKitGTK white-screen or EGL failures, try:

```bash
GDK_GL=disable WEBKIT_DISABLE_DMABUF_RENDERER=1 ./proton-drive_*.AppImage
```

The Rust app also sets WebKitGTK compatibility environment variables at startup, but package/runtime differences can still matter.

## License

This project is licensed under AGPL-3.0. See repository license metadata and package files for details.
