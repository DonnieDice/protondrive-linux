🐧 ProtonDrive Linux

Unofficial desktop GUI client for Proton Drive on Linux. Built with Tauri 2.0 and Rust.

## Status

**v1.1.3 — Working Beta**

| Format | Status | Notes |
|--------|--------|-------|
| AppImage | ✅ Working | Portable, no install needed |
| AUR | ✅ Working | Arch/Manjaro via `yay` |
| RPM | ✅ Working | Fedora, RHEL, CentOS |
| DEB | ✅ Working | Debian, Ubuntu, Mint |
| Flatpak | ⚠ Beta | Local `.flatpak` file — not on Flathub |
| Snap | ⚠ Beta | Local `.snap` file — not on Snapcraft |

Login, CAPTCHA, 2FA, app selection, Drive loading, and file browsing work. Downloads save to `~/Downloads`. Fedora/RPM launch has been validated locally.

## Branch Workflow

```
dev ──► alpha ──► main
 │         │        │
 │         │        └── Stable release (versioned tag, e.g. v1.1.3)
 │         └────────── Pre-release (alpha tag, e.g. v1.1.3-alpha)
 └──────────────────── Dev builds (pre-release tag, e.g. v1.1.3-dev)
```

- **`dev`** — active development, CI builds and publishes pre-release artifacts
- **`alpha`** — integration testing, pre-release artifacts
- **`main`** — stable releases only; merge from alpha after validation

All branches trigger the full build matrix (deb, rpm, AppImage, Flatpak, Snap).

## Installation

### Quick Install (AppImage — works everywhere)

```bash
chmod +x proton-drive_*.AppImage
./proton-drive_*.AppImage
```

### Debian / Ubuntu / Mint

```bash
sudo apt install ./proton-drive_*.deb
```

### Fedora / RHEL / CentOS

```bash
sudo dnf install ./proton-drive-*.rpm
```

### Arch Linux (AUR)

```bash
yay -S proton-drive-bin
```

### Flatpak (local bundle)

```bash
flatpak install --user proton-drive.flatpak
flatpak run com.proton.drive
```

> **Note:** Not available on Flathub. Download `proton-drive.flatpak` from the [Releases](https://github.com/DonnieDice/protondrive-linux/releases) page.

### Snap (local package)

```bash
sudo snap install --dangerous proton-drive_*.snap
```

> **Note:** Not available in the Snap Store. Download from [Releases](https://github.com/DonnieDice/protondrive-linux/releases).

## Building from Source

### Prerequisites

- **Node.js 18+** — `node --version`
- **Rust** — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **System deps (Fedora):** `sudo dnf install webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel openssl-devel`
- **System deps (Debian/Ubuntu):** `sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev libssl-dev`

### Clone and Build

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux

# Clone WebClients (Proton's frontend)
git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients

# Build WebClients + Tauri
npm install
npm run build:web      # build frontend (patches, yarn install, webpack)
npm run build:rpm      # or build:deb, build:appimage
```

Built packages land in `src-tauri/target/release/bundle/`.

### Local dev run

```bash
npm run dev
```

## Architecture

```
protondrive-linux/
├── src-tauri/src/main.rs     Rust backend: API proxy, download handler, captcha flow
├── docs/debugging/           Debugging history and release validation notes
├── patches/common/           Source patches applied to WebClients before build
├── scripts/
│   ├── build-webclients.sh   Patch + build frontend (local)
│   ├── fix_deps.py           Strip private Proton deps, configure yarn registry
│   └── create_stubs.py       Stub private npm packages (@proton/collect-metrics)
└── .github/workflows/        CI: deb+rpm+appimage, flatpak, snap, release
```

**How it works:** The app wraps Proton Drive's official web frontend inside a Tauri WebView. A Rust proxy intercepts all `/api/` fetch calls and forwards them to Proton's servers with a persistent cookie jar (bypasses CORS). Auth, encryption, and file operations are handled entirely by Proton's JS — Rust sees nothing sensitive.

## Troubleshooting

### Login error: "undefined is not a constructor" (Worker)

Affects: RPM/DEB on Fedora, Ubuntu. Fixed in v1.1.2+.

If you see this on an older build, use the AppImage instead while upgrading.

### White screen / EGL crash on startup

```bash
# Try these environment flags
WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 ./proton-drive*.AppImage
```

Caused by a WebKitGTK bug on AMD/Wayland systems (WebKit [bug #280239](https://bugs.webkit.org/show_bug.cgi?id=280239)). The env vars are set automatically inside the binary in v1.1.2+.

### Chunk loading error after login (locales, date-fns)

```
Loading chunk failed. (/account/assets/static/locales/nl_NL.*.chunk.js)
```

Fixed in v1.1.3+ by disabling Webpack SRI at build time and correcting nested Account/Verify public paths. If you're building from source, make sure you're on `main` or a recent `dev` build.

### Login refresh loop / CAPTCHA freezes

Fixed in v1.1.3+ — API challenge iframes are blocked from document navigation, CAPTCHA runs as a top-level verification page, and the completed verification token is passed back to the Account app for the retried auth request.

### App stuck on loading screen

- Check internet connection — the app needs live access to Proton's servers
- Try launching from terminal to see error output
- Report the terminal log as an issue

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Branch your work off `dev`, not `main`. Maintainer/agent notes live in [AGENTS.md](AGENTS.md).

## License

AGPL-3.0 — see [LICENSE](LICENSE).
