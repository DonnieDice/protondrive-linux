# Compatibility Baseline Roadmap

## Core Principle

```text
One universal Linux app
Many delivery channels
Few compatibility baselines
Broad test matrix
```

Build fewer packages. Test more systems. Split only when a patch/runtime difference proves necessary.

## Clean Base Rule

**The base binary (`src-tauri/src/main.rs`) must never contain distro-specific env vars, DISTRO_TYPE branching, or any distro/version-specific code.** The base ships clean. All WebKitGTK env vars, sandbox overrides, renderer flags, and distro-specific behavior belong exclusively in `patches/<package>/<distro>.<version>.patch`.

If a distro-specific value appears in `main.rs`, it is a bug. The only acceptable content in `main.rs` for these settings is the placeholder comment:

```rust
// NOTE: WebKitGTK env vars (GDK_GL, WEBKIT_DISABLE_*, etc.) are NOT set here.
// They are distro-specific and belong in patches/<package>/<distro>.patch
// and the package's AppRun/wrapper script. The base binary ships clean.
```

This ensures every build starts from the same clean baseline and diverges only through its patch.

## Definitions

| Term | Meaning |
|------|---------|
| **Build target** | Where/how the package is compiled (container image + patch set) |
| **Compatibility range** | Where that package is expected to work |
| **Test target** | Each distro/version you verify |
| **Release asset** | What the user downloads |

## Decision Rule

Add a new compatibility package **only** when one of these is true:

- A different patch set is required
- A different build container is required
- A system dependency name/version differs
- A runtime WebKitGTK/GTK behavior differs
- The package installs but fails launch/login/CAPTCHA/Drive load
- The package manager metadata requires a different dependency set

Do **not** add a new package only because a distro has a different brand name.

---

## RPM

### Compatibility Baselines

| Build target | Build container | Compatibility range | Release asset |
|-------------|----------------|---------------------|---------------|
| `fedora40-compat` | `fedora:40` | Fedora 40, Fedora 41 | `proton-drive-${VERSION}-fedora40-41.x86_64.rpm` |
| `fedora42-compat` | `fedora:42` | Fedora 42, Fedora 43, Fedora 44 | `proton-drive-${VERSION}-fedora42-44.x86_64.rpm` |

### Patch Layout

```text
patches/rpm/
├── common/
│   └── (patches shared by all RPM builds)
├── fedora40-compat/
│   └── (Fedora 40/41: WEBKIT_FORCE_SANDBOX=0, GDK_GL=disable)
└── fedora42-compat/
    └── (Fedora 42+: WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1, JSC_useWasmIPInt=false, GDK_GL=disable)
```

### Build Commands

```bash
scripts/build-local-rpm.sh --rpm-target fedora40-compat
scripts/build-local-rpm.sh --rpm-target fedora42-compat
```

### CI Jobs

| Job | Container | Target | Artifact |
|-----|-----------|--------|----------|
| `build-rpm-fedora40-compat` | `fedora:40` | `fedora40-compat` | `rpm-fedora40-compat` |
| `build-rpm-fedora42-compat` | `fedora:42` | `fedora42-compat` | `rpm-fedora42-compat` |

### Supported Mapping

```text
Fedora 40 → fedora40-41 RPM
Fedora 41 → fedora40-41 RPM
Fedora 42 → fedora42-44 RPM
Fedora 43 → fedora42-44 RPM
Fedora 44 → fedora42-44 RPM
```

If Fedora 44 later needs a different patch, split `fedora42-compat` into `fedora42-43` and `fedora44`.

### Known Differences

| Baseline | Sandbox var | WASM interpreter | GDK_GL |
|----------|-------------|-------------------|--------|
| `fedora40-compat` | `WEBKIT_FORCE_SANDBOX=0` | Default (JIT) | `disable` |
| `fedora42-compat` | `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` | `JSC_useWasmIPInt=false` (LLInt) | `disable` |

---

## DEB

### Compatibility Baselines

| Build target | Build container | Compatibility range | Release asset |
|-------------|----------------|---------------------|---------------|
| `debian12-compat` | `debian:12` | Debian 12 | `proton-drive_${VERSION}_debian12_amd64.deb` |
| `debian13-compat` | `debian:13` | Debian 13 | `proton-drive_${VERSION}_debian13_amd64.deb` |
| `ubuntu22.04-compat` | `ubuntu:22.04` | Ubuntu 22.04, Linux Mint 21.x, Zorin 17, Pop!_OS 22.04 | `proton-drive_${VERSION}_ubuntu22.04_amd64.deb` |
| `ubuntu24.04-compat` | `ubuntu:24.04` | Ubuntu 24.04, Linux Mint 22.x, Pop!_OS 24.04 | `proton-drive_${VERSION}_ubuntu24.04_amd64.deb` |

### Patch Layout

```text
patches/deb/
├── common/
├── debian12-compat/
├── debian13-compat/
├── ubuntu22.04-compat/
└── ubuntu24.04-compat/
```

### Build Commands

```bash
scripts/build-local-deb.sh --deb-target debian12-compat
scripts/build-local-deb.sh --deb-target debian13-compat
scripts/build-local-deb.sh --deb-target ubuntu22.04-compat
scripts/build-local-deb.sh --deb-target ubuntu24.04-compat
```

### Known Differences

| Baseline | GDK_GL | Reason |
|----------|--------|--------|
| `ubuntu24.04-compat` | `software` | `GDK_GL=disable` crashes WebKitWebProcess on Ubuntu 24.04+ |
| `debian12-compat` | `disable` | Safe on Debian; also sets `LIBGL_ALWAYS_SOFTWARE=1` |

---

## AppImage

### Compatibility Baseline

| Build target | Build container | Compatibility range | Release asset |
|-------------|----------------|---------------------|---------------|
| `appimage-arch` | `archlinux:base-devel` | Arch | `proton-drive_${VERSION}_arch_amd64.AppImage` |
| `appimage-manjaro` | `archlinux:base-devel` | Manjaro | `proton-drive_${VERSION}_manjaro_amd64.AppImage` |
| `appimage-ubuntu2404` | `ubuntu:24.04` | Ubuntu 24.04+ | `proton-drive_${VERSION}_ubuntu.24.04_amd64.AppImage` |

### Patch Layout

```text
patches/appimage/
├── common/
├── arch/
│   └── arch.patch
├── manjaro/
│   └── manjaro.patch
└── ubuntu.24.04/
    └── ubuntu.24.04.patch
```

### AppRun Wrappers

Each AppImage target includes a static AppRun with hardcoded env vars — no runtime `/etc/os-release` detection. This follows the same clean-base principle as RPM/DEB: the patch sets compile-time env vars, the AppRun sets runtime env vars, both specific to the target distro.

| Target | GDK_GL | Sandbox | WASM | Notes |
|--------|--------|---------|------|-------|
| `arch` / `manjaro` | `disable` | `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` | `JSC_useWasmIPInt=false` | webkit2gtk 2.52+ |
| `ubuntu.24.04` | `software` | `WEBKIT_FORCE_SANDBOX=0` | default | GDK_GL=disable crashes |

### Build Commands

```bash
scripts/build-local-appimage.sh --appimage-target arch
scripts/build-local-appimage.sh --appimage-target manjaro
scripts/build-local-appimage.sh --appimage-target ubuntu.24.04
```

### CI Jobs

| Job | Container | Target | Artifact |
|-----|-----------|--------|----------|
| `build-appimage-arch` | `debian:12` | `arch` | `appimage-arch` |
| `build-appimage-manjaro` | `debian:12` | `manjaro` | `appimage-manjaro` |
| `build-appimage-ubuntu2404` | `debian:12` | `ubuntu.24.04` | `appimage-ubuntu2404` |

---

## AUR

### Compatibility Baseline

| Build target | Build container | Compatibility range | Release asset |
|-------------|----------------|---------------------|---------------|
| `aur-arch` | `archlinux:base-devel` | Arch | PKGBUILD + wrapper + .SRCINFO |
| `aur-manjaro` | `archlinux:base-devel` | Manjaro | PKGBUILD + wrapper + .SRCINFO |
| `aur-endeavour` | `archlinux:base-devel` | EndeavourOS | PKGBUILD + wrapper + .SRCINFO |
| `aur-garuda` | `archlinux:base-devel` | Garuda | PKGBUILD + wrapper + .SRCINFO |

AUR uses the AppImage release asset as its source package input. Each target installs a distro-specific wrapper script at `/usr/bin/proton-drive` that sets WebKitGTK env vars before launching the binary at `/usr/lib/proton-drive/proton-drive.bin`.

### Patch Layout

```text
patches/aur/
├── common/
├── arch.patch
├── arch.wrapper
├── manjaro.patch
├── manjaro.wrapper
├── endeavour.patch
├── endeavour.wrapper
├── garuda.patch
└── garuda.wrapper
```

### Wrapper Scripts

Each AUR target has a static wrapper script — no runtime `/etc/os-release` detection.

| Target | GDK_GL | Sandbox | WASM | Notes |
|--------|--------|---------|------|-------|
| `arch` / `manjaro` / `endeavour` / `garuda` | `disable` | `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` | `JSC_useWasmIPInt=false` | webkit2gtk 2.52+ |

### Build Commands

```bash
scripts/build-local-aur.sh --aur-target arch
scripts/build-local-aur.sh --aur-target manjaro
scripts/build-local-aur.sh --aur-target endeavour
scripts/build-local-aur.sh --aur-target garuda
```

---

## Flatpak (Deferred)

Restore after native packages are green.

| Build target | Build container | Release asset |
|-------------|----------------|---------------|
| `flatpak-generic` | TBD | `proton-drive_${VERSION}_x86_64.flatpak` |

---

## Snap (Deferred)

Restore after native packages are green.

| Build target | Build container | Release asset |
|-------------|----------------|---------------|
| `snap-generic` | TBD | `proton-drive_${VERSION}_amd64.snap` |

---

## Deferred Packages

These are not built until a proven need arises:

- openSUSE-native RPM
- RHEL/Rocky/Alma RPM
- Mint/Zorin/Pop-specific DEBs (use the Ubuntu baseline instead)

---

## Source of Truth

`packaging/compatibility-map.yml` is the machine-readable compatibility map. See that file for build targets, artifact names, release labels, and supported distro mappings.

---

## Target Repository Structure

```text
protondrive-linux/
├── .github/workflows/
│   ├── build-rpm.yml              # Two jobs: fedora40-compat, fedora42-compat
│   ├── build-deb.yml              # Four jobs: debian12, debian13, ubuntu22.04, ubuntu24.04
│   ├── build-appimage.yml         # One job: appimage-generic
│   ├── build-aur.yml              # One job: validate PKGBUILD + .SRCINFO
│   ├── build-flatpak.yml          # Deferred
│   ├── build-snap.yml             # Deferred
│   ├── test-packages.yml          # Optional: smoke-test matrix
│   ├── generate-package-specs.yml
│   └── release.yml
├── patches/
│   ├── common/ # Shared WebClients patches (all builds)
│   ├── rpm/
│   │   ├── common/
│   │   ├── fedora40-compat/
│   │   └── fedora42-compat/
│   ├── deb/
│   │   ├── common/
│   │   ├── debian12-compat/
│   │   ├── debian13-compat/
│   │   ├── ubuntu22.04-compat/
│   │   └── ubuntu24.04-compat/
│   ├── appimage/
│   │   ├── common/
│   │   ├── arch/
│   │   ├── manjaro/
│   │   └── ubuntu.24.04/
│   ├── aur/
│   │   ├── common/
│   │   ├── arch.patch + arch.wrapper
│   │   ├── manjaro.patch + manjaro.wrapper
│   │   ├── endeavour.patch + endeavour.wrapper
│   │   └── garuda.patch + garuda.wrapper
│ ├── flatpak/
│ │ └── common/
│ └── snap/
│     └── common/
├── scripts/
│   ├── build-webclients.sh
│   ├── apply-patches.sh           # Shared patch application helper
│   ├── build-local-rpm.sh         # --rpm-target <compat-target> [--skip-webclient]
│   ├── build-local-deb.sh         # --deb-target <compat-target> [--skip-webclient]
│   ├── build-local-appimage.sh    # [--skip-webclient]
│   ├── fix_deps.py
│   └── create_stubs.py
├── packaging/
│   └── compatibility-map.yml      # Machine-readable compatibility source of truth
├── docs/
│   ├── packaging.md
│   ├── compatibility.md           # This document
│   └── release.md
└── src-tauri/
```

---

## Release Download Table

| System | Download |
|--------|----------|
| Fedora 40 / 41 | `proton-drive-*-fedora40-41.x86_64.rpm` |
| Fedora 42 / 43 / 44 | `proton-drive-*-fedora42-44.x86_64.rpm` |
| Debian 12 | `proton-drive_*_debian12_amd64.deb` |
| Debian 13 | `proton-drive_*_debian13_amd64.deb` |
| Ubuntu 22.04 / Mint 21.x / Zorin 17 / Pop!_OS 22.04 | `proton-drive_*_ubuntu22.04_amd64.deb` |
| Ubuntu 24.04 / Mint 22.x | `proton-drive_*_ubuntu24.04_amd64.deb` |
| Arch | AppImage: `proton-drive_*_arch_amd64.AppImage` or AUR: `proton-drive-bin` |
| Manjaro | AppImage: `proton-drive_*_manjaro_amd64.AppImage` or AUR: `proton-drive-bin` |
| EndeavourOS | AUR: `proton-drive-bin` |
| Garuda | AUR: `proton-drive-bin` (best-effort) |
| Ubuntu 24.04+ | AppImage: `proton-drive_*_ubuntu.24.04_amd64.AppImage` or DEB |
| Other Linux distributions | Build from source or try nearest AppImage |

---

## Typical Release

```text
RPM  (2 files)
  proton-drive-1.1.6-fedora40-41.x86_64.rpm
  proton-drive-1.1.6-fedora42-44.x86_64.rpm

DEB  (4 files)
  proton-drive_1.1.6_debian12_amd64.deb
  proton-drive_1.1.6_debian13_amd64.deb
  proton-drive_1.1.6_ubuntu22.04_amd64.deb
  proton-drive_1.1.6_ubuntu24.04_amd64.deb

AppImage (3 files)
proton-drive_1.1.6_arch_amd64.AppImage
proton-drive_1.1.6_manjaro_amd64.AppImage
proton-drive_1.1.6_ubuntu.24.04_amd64.AppImage

AUR (4 channels)
PKGBUILD + wrapper + .SRCINFO published per distro target

Verification (1 file)
SHA256SUMS
```

**Total: 9 release artifacts + 4 AUR channels covering the major Linux desktop distros.**

---

## Implementation Phases

### Phase 1 — RPM Compat Baseline (current)

- [ ] Create `patches/rpm/common/`, `patches/rpm/fedora40-compat/`, `patches/rpm/fedora42-compat/`
- [ ] Move `patches/rpm/fedora.40.patch` → `patches/rpm/fedora40-compat/`
- [ ] Move `patches/rpm/fedora.42.patch` → `patches/rpm/fedora42-compat/`
- [ ] Delete `patches/rpm/fedora.43.patch` (absorbed by `fedora42-compat`)
- [ ] Rewrite `scripts/build-local-rpm.sh` with `--rpm-target` support
- [ ] Delete `scripts/rpm/build-local-rpm.fedora.40.sh`, `.fedora.42.sh`, `.fedora.43.sh`
- [ ] Replace `.github/workflows/build-rpm.fedora.40.yml` + `build-rpm.fedora.42.yml` → `build-rpm.yml` (two jobs)
- [ ] Create `packaging/compatibility-map.yml`
- [ ] Validate: local build for both targets, CI workflow passes

### Phase 2 — DEB Compat Baseline

- [ ] Create `patches/deb/common/`, `patches/deb/debian12-compat/`, `patches/deb/debian13-compat/`, `patches/deb/ubuntu22.04-compat/`, `patches/deb/ubuntu24.04-compat/`
- [ ] Move existing DEB patches into compat directories
- [ ] Rewrite `scripts/build-local-deb.sh` with `--deb-target` support
- [ ] Consolidate DEB workflows into `build-deb.yml` (four jobs)
- [ ] Validate: local build for each target, CI workflow passes

### Phase 3 — AppImage / AUR Alignment

- [x] Create per-distro AppImage patches: `patches/appimage/arch.patch`, `manjaro.patch`, `ubuntu.24.04.patch`
- [x] Remove runtime `/etc/os-release` detection from AppRun — each target gets a static AppRun
- [x] Create per-distro AUR patches + wrapper scripts: `patches/aur/{arch,manjaro,endeavour,garuda}.{patch,wrapper}`
- [x] Rewrite `scripts/build-local-appimage.sh` with `--appimage-target` flag
- [x] Rewrite `scripts/build-local-aur.sh` with `--aur-target` flag
- [x] Update PKGBUILD to use wrapper script pattern (binary at `/usr/lib/proton-drive/proton-drive.bin`)
- [x] Update `build-appimage.yml` workflow for per-distro targets
- [x] Update `build-aur.yml` workflow for per-distro targets
- [x] Update `packaging/compatibility-map.yml` with new AppImage/AUR targets
- [ ] Test `appimage-manjaro` build on Manjaro
- [ ] Test `aur-manjaro` build on Manjaro
- [ ] Test `aur-arch` build on Arch
- [ ] Validate: CI workflows pass for all targets

### Phase 4 — Release Workflow Update

- [ ] Update `release.yml` to download compat-baseline artifacts
- [ ] Rename release assets using compatibility labels (e.g., `fedora40-41`, `ubuntu24.04`)
- [ ] Generate `SHA256SUMS` from renamed assets

### Phase 5 — Test Matrix

- [ ] Create `packaging/smoke-tests.yml` or `.github/workflows/test-packages.yml`
- [x] Test `fedora40-compat` RPM on Fedora 40, Fedora 41
- [x] Test `fedora42-compat` RPM on Fedora 42, Fedora 43
- [x] Test `fedora42-compat` RPM on Fedora 44 (validated — same webkit2gtk 2.52.3 as F42/F43)
- [x] Confirm `fedora40-compat` RPM does NOT work on Fedora 42+ (expected — missing webkit2gtk 2.52+ fixes)
- [x] Confirm `fedora40-compat` RPM does NOT work on Fedora 44 (crashes at 2FA — expected)
- [ ] Test DEB baselines on their respective distros
- [ ] Test AppImage arch/manjaro on their respective distros
- [ ] Test AUR arch/manjaro/endeavour/garuda on their respective distros

### Phase 6 — Deferred Packages

- [ ] Restore Flatpak workflow when native packages are stable
- [ ] Restore Snap workflow when native packages are stable
- [ ] Evaluate openSUSE-native RPM if testing reveals issues with `fedora42-compat` RPM
- [ ] Evaluate RHEL/Rocky/Alma RPM if demand exists

---

## Naming Convention (Authoritative)

### Build targets

```text
fedora40-compat
fedora42-compat
debian12-compat
debian13-compat
ubuntu22.04-compat
ubuntu24.04-compat
appimage-arch
appimage-manjaro
appimage-ubuntu2404
aur-arch
aur-manjaro
aur-endeavour
aur-garuda
```

### CI artifact names

```text
rpm-fedora40-compat
rpm-fedora42-compat
deb-debian12-compat
deb-debian13-compat
deb-ubuntu2204-compat
deb-ubuntu2404-compat
appimage-arch
appimage-manjaro
appimage-ubuntu2404
aur-arch-srcinfo
aur-manjaro-srcinfo
aur-endeavour-srcinfo
aur-garuda-srcinfo
```

### Release filenames

```text
proton-drive-${VERSION}-fedora40-41.x86_64.rpm
proton-drive-${VERSION}-fedora42-44.x86_64.rpm
proton-drive_${VERSION}_debian12_amd64.deb
proton-drive_${VERSION}_debian13_amd64.deb
proton-drive_${VERSION}_ubuntu22.04_amd64.deb
proton-drive_${VERSION}_ubuntu24.04_amd64.deb
proton-drive_${VERSION}_arch_amd64.AppImage
proton-drive_${VERSION}_manjaro_amd64.AppImage
proton-drive_${VERSION}_ubuntu.24.04_amd64.AppImage
SHA256SUMS
```
