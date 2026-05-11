🐧 ProtonDrive Linux

Unofficial desktop GUI client for Proton Drive on Linux. Built with Tauri 2.0 and Rust.

## Status

**v1.2.0 — Working Beta**

| Format | Status | Notes |
|--------|--------|-------|
| RPM | ✅ Validated | Fedora 43–44, el9, el10 (per-distro baselines, login, CAPTCHA, 2FA, Drive launch) |
| DEB | ✅ CI build | Debian 12/13, Ubuntu 22.04/24.04/26.04 |
| AppImage | ✅ CI build | Runtime target: `linux-baseline` (glibc 2.35+, webkit2gtk 2.46+) |
| AUR | ✅ CI build | Runtime target: `arch` (webkit2gtk 2.52+, covers Arch/Manjaro/Endeavour/Garuda) |
| Flatpak | ✅ CI build | Runtime target: `org.gnome.Platform.50` |
| Snap | ✅ CI build | Runtime targets: `core24`, `core26` |

Login, CAPTCHA, 2FA, app selection, Drive loading, and file browsing work. Downloads save to `~/Downloads`.

RPM is validated across Fedora baselines (43–44) and Enterprise Linux (el9, el10). Fedora 43+ and el10 patches include fixes for webkit2gtk 2.52+ (sandbox API change and IPInt WASM interpreter crash).

All packages use runtime/ABI-named patches — patches are named after the runtime target (e.g., `linux-baseline.patch`, `arch.patch`, `core24.patch`), not the host distro. No runtime `/etc/os-release` detection.

## Branch Workflow

```
dev ──► alpha ──► main
 │         │        │
│ │ └── Stable release (versioned tag, e.g. v1.2.0)
│ └────────── Pre-release (alpha tag, e.g. v1.2.0-alpha)
└──────────────────── Dev builds (pre-release tag, e.g. v1.2.0-dev)
```

- **`dev`** — active development, CI builds and publishes pre-release artifacts
- **`alpha`** — integration testing, pre-release artifacts
- **`main`** — stable releases only; merge from alpha after validation

Build and workflow fixes go to `dev` first. Stable releases are cut from `main` only after the required native package workflows are green.

Required release workflows:

- `build-rpm.fedora.43.yml`
- `build-rpm.fedora.44.yml`
- `build-deb.yml`
- `build-appimage.yml`
- `build-aur.yml`
- `build-flatpak.yml`
- `build-snap.yml`
- `generate-package-specs.yml`

Snap and Flatpak are intentionally not part of the current release gate.

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

### Arch / Manjaro (AUR)

```bash
yay -S proton-drive-bin
```

Or install a CI-built `.pkg.tar.zst` directly:

```bash
sudo pacman -U proton-drive-bin-*.pkg.tar.zst
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
- **System deps (Arch/Manjaro):** `sudo pacman -S webkit2gtk-4.1 gtk3 libayatana-appindicator`

### Clone and Build

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux

# Clone WebClients (Proton's frontend)
git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients

# Build WebClients + Tauri
npm install
npm run build:web    # build frontend (patches, yarn install, webpack)
npm run build:rpm    # or build:deb, build:appimage

# Or build AUR package locally
scripts/build-local-aur.sh --aur-target arch

# Or build AppImage locally
scripts/appimage/build-local-appimage.sh --appimage-target linux-baseline
```

Built packages land in `src-tauri/target/release/bundle/`.

### Local dev run

```bash
npm run dev
```

## Architecture

```text
protondrive-linux/
├── src-tauri/src/main.rs   Rust backend: API proxy, download handler, captcha flow
├── docs/                   Architecture, packaging, compatibility, troubleshooting
├── patches/
│   ├── common/              shared.patch (common WebKitGTK defaults)
│   ├── rpm/                 fedora.43, fedora.44, el9, el10
│   ├── deb/                 debian.12, debian.13, ubuntu.22.04, ubuntu.24.04, ubuntu.26.04
│   ├── appimage/            linux-baseline.patch
│   ├── aur/                 arch.patch + arch.wrapper
│   ├── flatpak/             org.gnome.Platform.50.patch
│   └── snap/                core24.patch, core26.patch
├── scripts/
│   ├── build-webclients.sh       Patch + build frontend (local)
│   ├── build-local-aur.sh        Build AUR .pkg.tar.zst locally
│   ├── appimage/build-local-appimage.sh  Build AppImage locally
│   ├── ci/build-aur-package.sh   CI helper: makepkg wrapper for AUR
│   ├── fix_deps.py               Strip private Proton deps, configure yarn registry
│   └── create_stubs.py           Stub private npm packages (@proton/collect-metrics)
└── .github/workflows/      CI: per-distro RPM, DEB, AppImage, AUR, specs, release
```

## Build Standards

- Keep package workflows separate by distro/package type.
- Keep package-specific behavior in that package workflow and `patches/<type>/`.
- Use `patches/common/` only for WebClients changes required by all builds.
- **Base code (`src-tauri/src/main.rs`) must never contain distro-specific env vars.** The base binary ships clean — zero distro/version-specific code. All WebKitGTK env vars, sandbox overrides, and renderer flags belong exclusively in `patches/<package>/<runtime>.patch` and the package's AppRun/wrapper script.
- Patches are named by runtime/ABI target (e.g., `linux-baseline`, `org.gnome.Platform.50`, `core24`, `el9`), not by host distro. No runtime `/etc/os-release` detection.
- Do not keep long-term distro branches for routine packaging differences.
- Use `dev` for test builds and workflow fixes; use `main` for stable release tags.
- Keep Snap and Flatpak separate from the native package release gate until they are restored.

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

Fixed in v1.1.5+ by disabling Webpack SRI at build time and correcting nested Account/Verify public paths. If you're building from source, make sure you're on `main` or a recent `dev` build.

### Login refresh loop / CAPTCHA freezes

Fixed in v1.1.5+ — API challenge iframes are blocked from document navigation, CAPTCHA runs as a top-level verification page, and the completed verification token is passed back to the Account app for the retried auth request.

### App stuck on loading screen

- Check internet connection — the app needs live access to Proton's servers
- Try launching from terminal to see error output
- Report the terminal log as an issue

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Branch your work off `dev`, not `main`. Packaging standards are in [docs/packaging.md](docs/packaging.md) and the compatibility baseline roadmap is in [docs/compatibility.md](docs/compatibility.md).

## License

AGPL-3.0 — see [LICENSE](LICENSE).
