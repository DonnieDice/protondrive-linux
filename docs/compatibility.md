# Compatibility Baseline Roadmap

## Core Principle

```text
One universal Linux app
Many delivery channels
Few compatibility baselines
Broad test matrix
```

Build fewer packages. Test more systems. Split only when a patch/runtime difference proves necessary.

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
| `appimage-generic` | `debian:12` | Any Linux x86_64 (best-effort) | `proton-drive_${VERSION}_amd64.AppImage` |

### Patch Layout

```text
patches/appimage/
└── common/
```

### Notes

AppImage is the portable fallback, not a guaranteed-works-everywhere package. WebKitGTK/GTK host compatibility is still required. Call it "portable fallback" in docs.

Use it for: openSUSE (until native RPM validated), Mageia, Void, NixOS (best-effort), older/unknown distros.

---

## AUR

### Compatibility Baseline

| Build target | Build container | Compatibility range | Release asset |
|-------------|----------------|---------------------|---------------|
| `aur-bin` | `archlinux:base-devel` | Arch, Manjaro, EndeavourOS, Garuda | PKGBUILD + .SRCINFO (published to AUR) |

AUR uses the AppImage release asset as its source package input.

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
│ ├── common/ # Shared WebClients patches (all builds)
│ ├── rpm/
│ │ ├── common/
│ │ ├── fedora40-compat/
│ │ └── fedora42-compat/
│ ├── deb/
│ │ ├── common/
│ │ ├── debian12-compat/
│ │ ├── debian13-compat/
│ │ ├── ubuntu22.04-compat/
│ │ └── ubuntu24.04-compat/
│ ├── appimage/
│ │ └── common/
│ ├── aur/
│ │ └── common/
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
| Arch / EndeavourOS / Manjaro | AUR: `proton-drive-bin` |
| Other Linux distributions | `proton-drive_*_amd64.AppImage` |

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

AppImage  (1 file)
  proton-drive_1.1.6_amd64.AppImage

AUR  (1 channel)
  PKGBUILD / .SRCINFO published to AUR

Verification  (1 file)
  SHA256SUMS
```

**Total: 8 release artifacts covering the major Linux desktop distros.**

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

- [ ] Move AppImage patches into `patches/appimage/common/`
- [ ] Align `scripts/build-local-appimage.sh` with the compat baseline pattern
- [ ] Ensure AUR validation workflow references AppImage release asset

### Phase 4 — Release Workflow Update

- [ ] Update `release.yml` to download compat-baseline artifacts
- [ ] Rename release assets using compatibility labels (e.g., `fedora40-41`, `ubuntu24.04`)
- [ ] Generate `SHA256SUMS` from renamed assets

### Phase 5 — Test Matrix

- [ ] Create `packaging/smoke-tests.yml` or `.github/workflows/test-packages.yml`
- [x] Test `fedora40-compat` RPM on Fedora 40, Fedora 41
- [x] Test `fedora42-compat` RPM on Fedora 42, Fedora 43
- [ ] Test `fedora42-compat` RPM on Fedora 44 (pending availability)
- [x] Confirm `fedora40-compat` RPM does NOT work on Fedora 42+ (expected — missing webkit2gtk 2.52+ fixes)
- [ ] Test DEB baselines on their respective distros
- [ ] Test AppImage on openSUSE, other distros

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
appimage-generic
aur-bin
```

### CI artifact names

```text
rpm-fedora40-compat
rpm-fedora42-compat
deb-debian12-compat
deb-debian13-compat
deb-ubuntu2204-compat
deb-ubuntu2404-compat
appimage-package
aur-srcinfo
```

### Release filenames

```text
proton-drive-${VERSION}-fedora40-41.x86_64.rpm
proton-drive-${VERSION}-fedora42-44.x86_64.rpm
proton-drive_${VERSION}_debian12_amd64.deb
proton-drive_${VERSION}_debian13_amd64.deb
proton-drive_${VERSION}_ubuntu22.04_amd64.deb
proton-drive_${VERSION}_ubuntu24.04_amd64.deb
proton-drive_${VERSION}_amd64.AppImage
SHA256SUMS
```
