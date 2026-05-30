# Build System & Packaging

## Build overview

```mermaid
flowchart LR
    subgraph "Source"
        RUST[src-tauri/ *.rs]
        MAINRS[Init Script in main.rs]
        WEB_CLIENTS["WebClients/ local checkout"]
    end

    subgraph "Build Script"
        SCRIPT["scripts/build-webclients.sh\nClone from GitHub → patch →\nbuild 3 SPAs in parallel"]
        CDN["applications/drive/dist/\n(Drive + Account + Verify)"]
    end

    subgraph "Patches"
        COMMON[patches/common/]
        PYSCRIPTS["scripts/fix_deps.py +\nscripts/patch_drive_linux_drawer.py +\nscripts/patch_drive_linux_sync_bridge.py"]
        DISTRO[patches/{deb,rpm,apk,...}/]
    end

    subgraph "CI/CD"
        TEST[test stage]
        BUILD_BUILD[build stage]
        VERIFY[verify stage]
        SPEC[spec stage]
        RELEASE[release stage]
        PUBLISH[publish stage]
    end

    WEB_CLIENTS --> SCRIPT
    COMMON --> SCRIPT
    PYSCRIPTS --> SCRIPT
    SCRIPT --> CDN
    CDN --> RUST
    RUST -->|cargo build| TEST
    TEST --> BUILD_BUILD
    BUILD_BUILD --> VERIFY
    VERIFY --> SPEC
    SPEC --> RELEASE
    RELEASE --> PUBLISH
```

## Two-part build

### Part 1: Web Clients

The Proton web SPA is NOT part of this repository. It comes from `github.com/ProtonMail/WebClients` (the private `gitlab.com/protonme/web-drive` was migrated).

`scripts/build-webclients.sh` (282 lines) orchestrates the full build:

1. **Cache-aware** — computes a cache key from WebClients HEAD + build script hashes + patch hashes; reuses `WebClients/applications/drive/dist/` when unchanged
2. **Clone or use local checkout** — checks `WebClients/` directory first; if missing, does `git clone --depth=1 github.com/ProtonMail/WebClients.git` using `$WEBCLIENTS_REF` (default: `main`)
3. **Patches dependencies** — runs `scripts/fix_deps.py` to patch `package.json` dependencies for CJS/ESM compat
4. **Applies common patches** — applies patch files from `patches/common/` and runs Python scripts (`patch_drive_linux_drawer.py`, `patch_drive_linux_sync_bridge.py`)
5. **Creates stubs** — runs `scripts/create_stubs.py` for private Proton npm packages
6. **Parallel build** — builds THREE apps concurrently via yarn workspaces:
   - `proton-drive build:web` — main Drive SPA
   - `proton-account build:web` — SSO/Account app
   - `proton-verify build:web` — Captcha/Verify app
7. **Copies and fixes paths** — Account and Verify apps are copied into `applications/drive/dist/account/` and `applications/drive/dist/verify/` respectively, with asset paths rewritten (`/assets/` → `/account/assets/`, base href fixed, SRI integrity stripped for tauri:// protocol compat)

Output directory: `WebClients/applications/drive/dist/` containing Drive, Account, and Verify SPAs.

### Part 2: Rust + Tauri

The `WebClients/applications/drive/dist/` directory content is bundled into the Tauri binary at compile time via the Tauri asset system. The `build.rs` is minimal:

```rust
fn main() {
    tauri_build::build()
}
```

Tauri's build process scans for assets and embeds them. The `protocol-asset` feature in `Cargo.toml` registers `tauri://localhost/` as a custom protocol to serve these assets:

```toml
tauri = { version = "2.0", features = ["protocol-asset"] }
```

Account, Drive, and Verify SPAs are all served from `tauri://localhost/` with paths like `tauri://localhost/account/` and `tauri://localhost/verify/` mapped to their respective build output directories.

## Patch system

The `patches/` directory contains organized patches applied during CI builds:

```
patches/
├── common/
│   ├── add-drive-linux-drawer-rail.patch      # Native sidebar (applied via Python script)
│   └── fix-tauri-worker-protocol.patch        # Worker protocol fix
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

Patches serve several purposes:
1. **Common patches** — modify the built SPA to work in the desktop shell (UI changes, protocol fixes)
2. **Python patch scripts** — `scripts/patch_drive_linux_drawer.py`, `scripts/patch_drive_linux_sync_bridge.py` — applied after common patches for complex transformations
3. **Distro patches** — distro-specific packaging metadata, dependency declarations, and build flags

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

The CI uses two systems:
- **GitHub Actions** (`.github/workflows/package-workflows.yml`) — primary packaging pipeline
- **GitLab CI** (`.gitlab-ci.yml` + `.gitlab/workflows/*.yml`) — test → build → verify → spec → release → publish on self-hosted GitLab at `192.168.1.31:8929`

The GitLab `.gitlab-ci.yml` is a thin 33-line entrypoint that includes workflows from `.gitlab/workflows/`:
- `_shared.yml` — shared job templates
- `tests.yml` — unit and integration tests
- `builds.yml` — per-distro build jobs
- `verify/*.yml` — per-distro VM verification (alpine, debian, ubuntu, fedora, opensuse, arch)
- `release.yml` — GitHub release creation

### Stages

```
test → build → verify → spec → release → publish
```

### Rules

| Pipeline source | Test | Build | Verify | Spec | Release | Publish |
|-----------------|------|-------|--------|------|---------|---------|
| Merge request | ✅ (auto) | ✅ (auto) | ❌ | ❌ | ❌ | ❌ |
| Branch push | ✅ (auto) | ✅ (auto) | ❌ | ❌ | ❌ | ❌ |
| `main` push | ✅ (auto) | ✅ (auto) | ✅ (auto) | ✅ (auto) | ✅ (auto) | ❌ |
| `v*` tag | ✅ (auto) | ✅ (auto) | ✅ (auto) | ✅ (auto) | ✅ (auto) | ✅ (manual) |

### Per-platform build jobs

Each platform has its own Docker-based build job with:
- Distro-specific base image (e.g., `alpine:3.20`, `fedora:44`)
- Distro-specific dependencies (WebKitGTK 4.1 dev, Rust toolchain, build tools)
- Python patch scripts applied via `scripts/fix_deps.py`, `scripts/patch_drive_linux_drawer.py`
- Cargo build with correct `DISTRO_TYPE`
- Artifact packaging (APK, DEB, RPM, AppImage, Flatpak)

### Verify stage

The `verify` stage spins up VMs matching each target distro to test the pre-built binary in an environment that matches end-user systems. Each distro has its own workflow file in `.gitlab/workflows/verify/`.

### Spec stage

The `spec` stage runs regression checks:
- `check-sync-regressions.sh` — Verifies sync command contract is intact
- `check-login-routing-regressions.sh` — Verifies SSO routing is intact

### Release stage

The `release` stage creates GitHub releases with per-platform artifacts. This runs automatically on `main` pushes and `v*` tags.

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

## See Also

- **[Build System](../architecture/build-system.md)** — Cargo feature flags, platform-specific notes, Tauri CLI
- **[Packaging](packaging.md)** — AppImage, deb, rpm packaging details
- **[CI Pipeline Reference](../ci-cd/ci-pipeline-reference.md)** — CI job matrix, artifact naming, release workflow
- **[New Build Checklist](new-build-checklist.md)** — Step-by-step build verification guide
