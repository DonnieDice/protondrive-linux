# CI/CD Workflows Documentation

This document explains the automated build and release workflows for Proton Drive Linux.

## Overview

The CI/CD pipeline automatically builds, packages, and releases Proton Drive for multiple platforms and Linux distributions whenever code is pushed, committed, or tagged.

## Workflows

### 1. **build-all-platforms.yml** (Main Build Pipeline)

**Triggers:** `push` to main/dev branches, tag push (v*), manual dispatch

**Purpose:** Comprehensive multi-platform build for all major operating systems

**Platforms:**
- Linux (DEB, RPM, AppImage)
- macOS (DMG, APP)
- Windows (MSI, NSIS)

**Jobs:**
- `build-linux`: Builds DEB, RPM, and AppImage packages
- `build-macos`: Builds macOS DMG and APP bundles
- `build-windows`: Builds Windows MSI and NSIS installers
- `prepare-release`: Collects all artifacts and generates checksums

**Artifacts:**
- `linux-builds`: Linux packages
- `macos-builds`: macOS packages
- `windows-builds`: Windows packages
- `release-packages`: Consolidated release files

**Duration:** ~90 minutes per platform

---

### 2. **build-flatpak.yml** (Flatpak Packaging)

**Triggers:** `push` to main/dev branches, tag push (v*), manual dispatch

**Purpose:** Build and bundle application as Flatpak

**Container:** `bilelmoussaoui/flatpak-github-actions:latest` (privileged)

**Artifacts:**
- `flatpak-bundle`: Binary Flatpak bundle (`.flatpak`)
- `flatpak-manifest`: Flatpak manifest file (`.yml`)

**Output Format:** Ready for distribution via Flathub

**Duration:** ~120 minutes

**Notes:**
- Requires privileged container
- Uses Freedesktop Platform 24.08
- Includes Rust SDK extension

---

### 3. **build-snap.yml** (Snap Packaging)

**Triggers:** `push` to main/dev branches, tag push (v*), manual dispatch

**Purpose:** Build Snap package for universal Linux distribution

**Architectures:** x86_64, ARM64

**Artifacts:**
- `snap-package`: Binary snap package (`.snap`)
- `snap-config`: snapcraft.yaml configuration

**Confinement:** Strict mode with necessary plugs (network, home, desktop, x11, wayland, dbus)

**Duration:** ~90 minutes

**Notes:**
- Uses `core24` base
- Includes desktop and DBus integration
- Supports multiple architectures

---

### 4. **build-linux-packages.yml** (Specialized Linux Builds)

**Triggers:** `push` to main/dev branches, tag push (v*), manual dispatch

**Purpose:** Builds for different Linux package formats with specialized handling

**Includes:**
- DEB packages (Debian/Ubuntu)
- RPM packages (Fedora/Red Hat/CentOS)
- AppImage (universal Linux)
- Flatpak manifest generation
- Snap manifest generation
- AUR PKGBUILD template
- Binary placeholders for container-based formats

**Artifacts:**
- `linux-packages`: DEB, RPM, AppImage
- `flatpak-manifest`: Flatpak manifest template
- `snap-manifest`: Snap manifest template
- `aur-package`: AUR PKGBUILD template

**Duration:** ~90 minutes

---

### 5. **publish-packages.yml** (Package Repository Publishing)

**Triggers:** Tag push (v*) only, manual dispatch

**Purpose:** Generate package files and metadata for various package repositories

**Jobs:**

#### 5.1 `publish-to-aur`
Generates AUR (Arch Linux User Repository) PKGBUILD file
- **Output:** Artifacts with ready-to-submit PKGBUILD
- **Manual Step:** Submit to AUR manually or via AUR maintainer

#### 5.2 `publish-copr`
Creates RPM spec file for COPR (Community Projects) repository
- **Output:** `.spec` file and `.copr/Makefile`
- **Supported:** Fedora Rawhide/Stable, CentOS Stream
- **Manual Step:** Build in COPR using web interface or copr-cli

#### 5.3 `create-source-dist`
Generates source distribution tarball
- **Output:** `.tar.gz` source package with checksums
- **Includes:** All source code except build artifacts
- **Size:** ~50-100MB (without WebClients and build artifacts)

**Duration:** ~30 minutes

---

### 6. **release.yml** (Release Management)

**Triggers:** Tag push (v*) only

**Purpose:** Create GitHub releases with build artifacts and release notes

**Features:**
- Generates release notes from commit history
- Creates GitHub Release automatically
- Includes installation instructions for all platforms
- Generates checksums section

**Release Notes Include:**
- Version and date information
- Installation instructions for each platform
- System requirements
- Known issues section
- Checksums for file verification

**Duration:** ~5 minutes

---

### 7. **web-build.yml** (Web Client Only)

**Triggers:** `push` to main/dev branches, pull requests

**Purpose:** Quick web client build verification

**Jobs:**
- Builds ProtonMail WebClients repository
- Verifies Proton Drive build output
- Generates build summary

**Artifacts:**
- `proton-drive-web-build`: Web client dist directory

**Duration:** ~30 minutes

**Notes:**
- Runs on all PRs to catch web client issues early
- Separate from desktop builds for faster feedback

---

## Triggered Events

### Push Events
- **To main:** All workflows trigger
- **To dev:** All workflows trigger (except release)
- **Tags (v*):** All workflows trigger (includes release creation)

### Manual Dispatch
All workflows can be triggered manually via GitHub Actions UI

### Pull Requests
- Only `web-build.yml` runs for faster feedback
- Full builds run only on main/dev branch pushes

---

## Build Artifacts and Retention

| Workflow | Artifact | Retention | Size |
|----------|----------|-----------|------|
| build-all-platforms | linux-builds | 30 days | ~500MB |
| build-all-platforms | macos-builds | 30 days | ~400MB |
| build-all-platforms | windows-builds | 30 days | ~300MB |
| build-flatpak | flatpak-bundle | 30 days | ~100MB |
| build-snap | snap-package | 30 days | ~150MB |
| publish-packages | aur-pkgbuild | 90 days | <1MB |
| publish-packages | source-distribution | 90 days | ~50MB |

---

## Package Formats by Distribution

### Ubuntu/Debian
- **Format:** DEB
- **Workflow:** build-all-platforms
- **Installation:** `sudo apt install ./proton-drive_*.deb`

### Fedora/RHEL/CentOS
- **Format:** RPM
- **Workflow:** build-all-platforms
- **Installation:** `sudo dnf install ./proton-drive-*.rpm`

### Arch Linux
- **Format:** PKG (via AUR)
- **Workflow:** publish-packages
- **Installation:** `yay -S proton-drive` or manual PKGBUILD

### Generic Linux (Universal)
- **Format:** AppImage
- **Workflow:** build-all-platforms
- **Installation:** `chmod +x *.AppImage && ./proton-drive_*.AppImage`

### Flatpak (All Distributions)
- **Format:** Flatpak
- **Workflow:** build-flatpak
- **Installation:** `flatpak install ./proton-drive.flatpak` or via Flathub
- **Status:** Ready for Flathub submission

### Snap (All Distributions)
- **Format:** Snap
- **Workflow:** build-snap
- **Installation:** `snap install proton-drive.snap --dangerous` or via Snap Store
- **Status:** Ready for Snap Store submission

### macOS
- **Format:** DMG, APP
- **Workflow:** build-all-platforms
- **Installation:** Drag & drop or run DMG installer

### Windows
- **Format:** MSI, NSIS
- **Workflow:** build-all-platforms
- **Installation:** Run installer executable

---

## CI/CD Flow Diagram

```
Commit/Push
    ↓
├─→ web-build.yml (Quick feedback) ─→ PR Check ✓
│
├─→ build-all-platforms.yml
│   ├─→ build-linux (DEB/RPM/AppImage)
│   ├─→ build-macos (DMG/APP)
│   ├─→ build-windows (MSI/NSIS)
│   └─→ prepare-release (Checksums)
│
├─→ build-flatpak.yml
│   └─→ flatpak-bundle + manifest
│
├─→ build-snap.yml
│   └─→ snap-package + config
│
└─→ build-linux-packages.yml (Parallel builds)

Tag Push (v*)
    ↓
├─→ [All above workflows]
│
├─→ publish-packages.yml
│   ├─→ publish-to-aur (PKGBUILD)
│   ├─→ publish-copr (RPM spec)
│   └─→ create-source-dist (tarball)
│
└─→ release.yml
    └─→ GitHub Release + Artifacts + Checksums
```

---

## Environment Variables

All workflows use:
- `NODE_VERSION: "22"` - Node.js version for web builds
- `RUST_VERSION: "stable"` - Rust toolchain version
- `PYTHONIOENCODING: utf-8` - For Windows Python compatibility

---

## System Requirements by Platform

### Linux (Ubuntu 24.04)
- GCC/build-essential
- libssl-dev, libwebkit2gtk-4.1-dev, libgtk-3-dev
- Python 3, Node.js, Rust/Cargo

### macOS
- Xcode Command Line Tools
- Rust toolchain
- Node.js

### Windows
- Visual Studio Build Tools (2019+) or MSVC
- Rust toolchain
- Node.js

---

## Troubleshooting

### Build Failures

1. **WebClients Dependency Issues**
   - Check `fix_deps.py` for dependency patching
   - Verify yarn/npm cache is clean

2. **Rust Compilation**
   - Clear Rust cache if updating toolchain
   - Check system library dependencies (libssl-dev, webkit2gtk)

3. **Node.js Memory**
   - Workflows set `NODE_OPTIONS="--max-old-space-size=8192"`
   - May need adjustment for WebClients builds

4. **Flatpak Build Failures**
   - Requires privileged container mode
   - Check base SDK version compatibility

5. **Snap Build Failures**
   - May require elevation to stable channel
   - Check snapcraft documentation for plugin issues

### Artifact Upload Failures

- Check artifact size limits (GitHub has 5GB per workflow run)
- Verify retention-days setting
- Ensure build output path is correct

---

## Manual Package Repository Submission

### AUR (Arch Linux User Repository)
1. Download PKGBUILD from `aur-pkgbuild` artifact
2. Update maintainer information
3. Test locally: `makepkg -si`
4. Submit to AUR: https://aur.archlinux.org/account/

### COPR (Community Projects)
1. Download spec file from `rpm-spec` artifact
2. Create COPR project: https://copr.fedorainfracloud.org/
3. Upload PKGBUILD or submit via `fedpkg`

### Flathub
1. Download flatpak manifest from `flatpak-manifest` artifact
2. Submit to Flathub: https://github.com/flathub/flathub

### Snap Store
1. Download snap package from `snap-package` artifact
2. Upload to Snap Store: https://snapcraft.io/
3. Configure automatic updates

---

## Best Practices

1. **Always test locally** before pushing tags
2. **Use semantic versioning** (v1.0.0, v1.0.1, etc.)
3. **Generate release notes** for each version
4. **Verify checksums** after download
5. **Monitor workflow duration** for performance issues
6. **Keep dependencies updated** in workflows

---

## Support

For issues or questions:
- Check GitHub Actions logs in repository
- Review workflow YAML files for details
- Consult official documentation:
  - [GitHub Actions](https://docs.github.com/en/actions)
  - [Tauri Building Guide](https://tauri.app/v1/guides/building/)
  - [Flatpak Guide](https://docs.flatpak.org/)
  - [Snapcraft Guide](https://snapcraft.io/docs/)
