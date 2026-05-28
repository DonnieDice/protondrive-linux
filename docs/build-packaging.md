# Build System & Packaging

## Build overview

```mermaid
flowchart LR
    subgraph "Source"
        RUST[src-tauri/ *.rs]
        SPINIT[Init Script in main.rs]
        ASSETS[src-tauri/assets/ Account app]
    end

    subgraph "Web Clients (build step)"
        DRIVE[protonme/web-drive SPA]
        WEBCLIENTS["scripts/build-webclients.sh\n→ cdn/ directory"]
    end

    subgraph "Patches"
        COMMON[patches/common/]
        DISTRO[patches/{deb,rpm,apk,...}/]
    end

    subgraph "CI/CD"
        APK[Alpine APK]
        DEB[Debian/Ubuntu DEB]
        RPM[Fedora/RHEL RPM]
        APPIMAGE[AppImage]
        AUR[Arch AUR]
        FLATPAK[Flatpak]
        SNAP[Snap]
    end

    DRIVE --> WEBCLIENTS
    WEBCLIENTS --> RUST
    RUST -->|cargo build| APK
    RUST -->|cargo build| DEB
    RUST -->|cargo build| RPM
    RUST -->|cargo build| APPIMAGE
    RUST -->|cargo build| AUR
    RUST -->|cargo build| FLATPAK
    RUST -->|cargo build| SNAP
    COMMON --> APK
    COMMON --> DEB
    DISTRO --> APK
    DISTRO --> DEB
```

## Two-part build

### Part 1: Web Clients

The Proton Drive SPA is NOT part of this repository. It comes from `gitlab.com/protonme/web-drive`.

```bash
# scripts/build-webclients.sh
# Clones web-drive at a pinned commit, builds Drive + Account SPAs
git clone https://gitlab.com/protonme/web-drive.git
cd web-drive
git checkout $WEBCLIENTS_COMMIT   # bbad1a0a482227b93a2e963a232463aede9b8abf

# Build Drive SPA
yarn install
yarn workspace @proton/drive build

# Copy output to cdn/
cp -r packages/drive/dist/* cdn/

# Build Account app for SSO
yarn workspace @proton/account build
cp -r packages/account/dist/* src-tauri/assets/account/
```

### Part 2: Rust + Tauri

The `cdn/` directory content is bundled into the Tauri binary at compile time. The `build.rs` is minimal:

```rust
fn main() {
    tauri_build::build()
}
```

Tauri's build process scans for assets and embeds them. The `protocol-asset` feature in `Cargo.toml` registers `tauri://localhost/` as a custom protocol to serve these assets:

```toml
tauri = { version = "2.0", features = ["protocol-asset"] }
```

The `src-tauri/assets/account/` directory contains the Account app for SSO. When the WebView navigates to `tauri://localhost/account/`, Tauri serves files from this directory.

## Patch system

The `patches/` directory contains organized patches applied during CI builds:

```
patches/
├── common/
│   ├── show-drive-drawer-rail-in-desktop-shell.patch  # UI adaptation
│   ├── fix-tauri-worker-protocol.patch                  # Worker protocol fix
│   └── add-drive-linux-drawer-rail.patch                # Native sidebar
├── deb/
│   ├── debian.12.patch
│   ├── debian.13.patch
│   ├── ubuntu.24.04.patch
│   └── ubuntu.26.04.patch
├── rpm/
│   ├── fedora.43.patch
│   ├── fedora.44.patch
│   ├── el10.patch
│   ├── opensuse.tumbleweed.patch
│   └── opensuse.leap.16.patch
├── apk/
│   ├── alpine.3.20.patch
│   ├── alpine.3.22.patch
│   └── alpine.3.23.patch
├── flatpak/
│   ├── org.gnome.Platform.49.patch
│   └── org.gnome.Platform.50.patch
├── appimage/
│   └── linux-baseline.patch
├── aur/
│   └── arch-native.patch
└── snap/
    ├── core24.patch
    └── core26.patch
```

Patches serve two purposes:
1. **Common patches** — modify the built SPA to work in the desktop shell (UI changes, protocol fixes)
2. **Distro patches** — distro-specific packaging metadata, dependency declarations, and build flags

## DISTRO_TYPE build variable

The `DISTRO_TYPE` environment variable determines how the app handles Web Workers at runtime:

```rust
let worker_init = match option_env!("DISTRO_TYPE") {
    Some("appimage") | Some("aur") => {
        // Native Workers supported — no override needed
    }
    Some("rpm") | Some("deb") | Some("flatpak") | Some("snap") | None => {
        // System WebKitGTK — disable Workers
        // window.Worker = undefined;
        // window.SharedWorker = undefined;
    }
    _ => {
        // Unknown — aggressive blocking with error suppression
    }
};
```

| DISTRO_TYPE | Worker handling | Why |
|---|---|---|
| `appimage` | Native Workers | Bundles its own WebKitGTK that supports Workers |
| `aur` | Native Workers | Arch's package builds with system WebKitGTK which supports Workers |
| `rpm`, `deb`, `flatpak`, `snap` | Workers disabled | System/sandboxed WebKitGTK — Workers often throw "operation is insecure" |
| None (default) | Workers disabled | Safe default for unknown contexts |

## Packaging formats

### Compatibility Gates

All packaging targets are defined in `packaging/compatibility-map.yml`. Each target must pass two gates:

| Gate | Requirement |
|------|-------------|
| **glibc** | ≥ 2.35 (or musl for Alpine, runtime for Flatpak/Snap) |
| **webkitgtk** | WebKitGTK 4.1 available in target repos |

### Active targets (release-gated)

| Format | Targets | Runtime engine |
|--------|---------|----------------|
| **DEB** | Debian 12/13, Ubuntu 24.04/26.04 | System WebKitGTK |
| **RPM** | Fedora 43/44, EL10, openSUSE Tumbleweed | System WebKitGTK |
| **APK** | Alpine 3.20/3.22/3.23 (musl) | System WebKitGTK (musl-compiled) |
| **AppImage** | Linux baseline (glibc 2.35+) | Bundled WebKitGTK |
| **AUR** | Arch, Manjaro, Endeavour, Garuda (native build) | System WebKitGTK |
| **Flatpak** | GNOME Platform 49/50 | Runtime WebKitGTK |
| **Snap** | core24/core26 (currently blocked) | Runtime WebKitGTK |

### Architecture support

| Arch | Status |
|------|--------|
| `x86_64` | Release-gated (current artifact) |
| `aarch64` | Planned |
| `armv7` | Legacy (needs WebKitGTK verification) |
| `riscv64` | Experimental |

### Cargo config for Alpine (musl)

Alpine builds use musl instead of glibc and require special Cargo config:

```toml
[target.x86_64-unknown-linux-musl]
linker = "gcc"
rustflags = ["-C", "target-feature=-crt-static"]
```

## CI/CD Pipeline

The CI is on self-hosted GitLab at `192.168.1.31:8929`. The pipeline file is `.gitlab-ci.yml` (1,492 lines).

### Stages

```
build → spec → release → publish
```

### Rules

| Pipeline source | Build | Release | Publish |
|-----------------|-------|---------|---------|
| Merge request | ✅ (auto) | ❌ | ❌ |
| Branch push | ✅ (auto) | ❌ | ❌ |
| `main` push | ✅ (auto) | ✅ (auto) | ❌ |
| `v*` tag | ✅ (auto) | ✅ (auto) | ✅ (manual) |

### Per-platform build jobs

Each platform has its own Docker-based build job with:
- Distro-specific base image (e.g., `alpine:3.20`, `fedora:44`)
- Distro-specific dependencies (WebKitGTK 4.1 dev, Rust toolchain, build tools)
- Patch application
- Cargo build with correct `DISTRO_TYPE`
- Artifact packaging (APK, DEB, RPM, AppImage, Flatpak)

### Common CI build script anchors

```yaml
.install_rust: &install_rust |
  export PATH="$CARGO_HOME/bin:$PATH"
  if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
      sh -s -- -y --default-toolchain "${RUST_VERSION}" --no-modify-path
  fi
  rustc --version && cargo --version
```

### Spec stage

The `spec` stage runs regression checks:
- `check-sync-regressions.sh` — Verifies sync command contract is intact
- `check-login-routing-regressions.sh` — Verifies SSO routing is intact

### Release stage

The `release` stage in `.gitlab-ci.yml` creates GitHub releases with per-platform artifacts. This runs automatically on `main` pushes and `v*` tags.

### Publish stage

The `publish` stage distributes to package registries:
- **AUR**: Pushes to AUR via `publish_aur` workflow (manual on `v*` tags)
- **Snap**: Pushes to Snap Store (manual on `v*` tags)
- **Flatpak**: Pushes to Flathub (manual on `v*` tags)

## Local build

```bash
# 1. Build web clients (requires Node.js + yarn)
./scripts/build-webclients.sh

# 2. Install system dependencies
# Debian/Ubuntu:
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev

# Fedora:
sudo dnf install webkit2gtk4.1-devel gtk3-devel

# Arch:
sudo pacman -S webkit2gtk-4.1

# 3. Build
cd src-tauri
DISTRO_TYPE=aur cargo build --release
```

Output binary: `src-tauri/target/release/proton-drive`
