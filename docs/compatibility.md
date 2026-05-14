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

**The base binary (`src-tauri/src/main.rs`) must never contain distro-specific env vars, DISTRO_TYPE branching, or any distro/version-specific code.** The base ships clean. All WebKitGTK env vars, sandbox overrides, renderer flags, and distro-specific behavior belong exclusively in `patches/<package>/<runtime>.patch`. Patches are named after the runtime/ABI target (e.g., `linux-baseline`, `org.gnome.Platform.49`, `org.gnome.Platform.50`, `core24`, `fedora.43`), not the host distro.

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

## Patch Tree

```text
patches/
├── common/
│ └── fix-tauri-worker-protocol.patch # WebClients tauri:// worker protocol fix
├── appimage/
│   └── linux-baseline.patch  # AppImage universal (glibc 2.35+, webkit2gtk 2.46+)
├── deb/
│   ├── debian.12.patch       # Debian 12 (webkit2gtk 2.40, GDK_GL=disable)
│   ├── debian.13.patch       # Debian 13 (webkit2gtk 2.46+, GDK_GL=software)
│   ├── ubuntu.24.04.patch    # Ubuntu 24.04 (webkit2gtk 2.46+, GDK_GL=software, JSC_useWasmIPInt=false)
│   └── ubuntu.26.04.patch    # Ubuntu 26.04 (webkit2gtk 2.48+, GDK_GL=software, JSC_useWasmIPInt=false)
├── rpm/
│   ├── fedora.43.patch       # Fedora 43 (webkit2gtk 2.52+, sandbox+IPInt fix)
│   ├── fedora.44.patch       # Fedora 44 (webkit2gtk 2.52+, sandbox+IPInt fix)
│   └── el10.patch            # RHEL 10 / CentOS Stream 10 / Alma 10 / Rocky 10
├── flatpak/
│   ├── org.gnome.Platform.49.patch  # GNOME Platform 49 runtime, JSC_useWasmIPInt=false
│   └── org.gnome.Platform.50.patch  # GNOME Platform 50 runtime, JSC_useWasmIPInt=false
├── snap/
│   ├── core24.patch          # Snap core24 base
│   └── core26.patch          # Snap core26 base (webkit2gtk 2.52+)
└── aur/
    ├── arch.patch            # Arch-family (webkit2gtk 2.52+)
    └── arch.wrapper          # Runtime wrapper for /usr/bin/proton-drive
```

---

## RPM

### Compatibility Baselines

| Build target | Build container | Compatibility range | Patch |
|-------------|----------------|---------------------|-------|
| `fedora43` | `fedora:43` | Fedora 43 | `fedora.43` |
| `fedora44` | `fedora:44` | Fedora 44 | `fedora.44` |
| `el10` | `centos:stream10` | RHEL 10, CentOS Stream 10, Alma 10, Rocky 10 | `el10` |

### Known Differences

| Baseline | Sandbox var | WASM interpreter | GDK_GL | Reason |
|----------|-------------|-------------------|--------|--------|
| `fedora.43` | `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` | `JSC_useWasmIPInt=false` | `disable` | webkit2gtk 2.52+ sandbox API change + IPInt SIGTRAP |
| `fedora.44` | `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` | `JSC_useWasmIPInt=false` | `disable` | Same as F43 |
| `el10` | `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` | `JSC_useWasmIPInt=false` | `disable` | webkit2gtk 2.52+ |

---

## DEB

### Compatibility Baselines

| Build target | Build container | Runtime smoke host | Compatibility range | Patch |
|-------------|----------------|--------------------|---------------------|-------|
| `debian12` | `debian:12` | Debian 12 | Debian 12 | `debian.12` |
| `debian13` | `debian:13` | Debian 13 | Debian 13 | `debian.13` |
| `ubuntu24.04` | `ubuntu:24.04` | Ubuntu 24.04 | Ubuntu 24.04, Linux Mint 22.x | `ubuntu.24.04` |
| `ubuntu26.04` | `ubuntu:26.04` | Ubuntu 26.04 | Ubuntu 26.04 | `ubuntu.26.04` |

DEB compatibility is target-release-specific. Do not count a Debian DEB test on Ubuntu, or an Ubuntu DEB test on a different Ubuntu release, as compatibility evidence for the target release.

### Known Differences

| Baseline | GDK_GL | Reason |
|----------|--------|--------|
| `debian.12` | `disable` | Safe on older WebKitGTK 2.40; sets `LIBGL_ALWAYS_SOFTWARE=1` |
| `debian.13` | `software` | `GDK_GL=disable` crashes WebKitWebProcess on 2.46+ |
| `ubuntu.24.04` | `software` | `GDK_GL=disable` crashes on 2.46+; `LIBGL_ALWAYS_SOFTWARE=1` keeps Mesa on software rendering; `JSC_useWasmIPInt=false` avoids the post-2FA WebKit/JSC trap path |
| `ubuntu.26.04` | `software` | Same as 24.04 for newer WebKitGTK; also requires `JSC_useWasmIPInt=false` |

---

## AppImage

| Build target | Build container | Compatibility range | Patch |
|-------------|----------------|---------------------|-------|
| `linux-baseline` | `debian:12` | All Linux with glibc 2.35+, webkit2gtk 2.46+ | `linux-baseline` |

AppImage is host-distro portable. The compatibility boundary is glibc age — build on the oldest supported baseline (Debian 12). Single `linux-baseline` target, `GDK_GL=software`, `JSC_useWasmIPInt=false` (avoids the post-2FA WebKit/JSC trap path).

---

## AUR

| Build target | Build container | Compatibility range | Patch |
|-------------|----------------|---------------------|-------|
| `arch` | `archlinux:base-devel` | Arch, Manjaro, EndeavourOS, Garuda | `arch` |

A single `arch` patch and wrapper covers all Arch-family distros — they share the same webkit2gtk version and env var requirements. Binary at `/usr/lib/proton-drive/proton-drive.bin`, wrapper at `/usr/bin/proton-drive`.

---

## Flatpak

| Build target | Build container | Patch |
|-------------|----------------|-------|
| `org.gnome.Platform.49` | `ubuntu-24.04` | `org.gnome.Platform.49` |
| `org.gnome.Platform.50` | `ubuntu-24.04` | `org.gnome.Platform.50` |

Patches target the Flatpak runtime, not the host distro.

---

## Snap

| Build target | Build container | Patch |
|-------------|----------------|-------|
| `core24` | `ubuntu-24.04` | `core24` |
| `core26` | `ubuntu-24.04` | `core26` |

Patches target the Snap base, not the host distro. `core24` is the Ubuntu 24.04-era base, and `core26` includes webkit2gtk 2.52+ sandbox and IPInt fixes.

---

## Release Download Table

| System | Download |
|--------|----------|
| Fedora 43 | `proton-drive-*.rpm` (fedora43) |
| Fedora 44 | `proton-drive-*.rpm` (fedora44) |
| RHEL 10 / Alma 10 / Rocky 10 | `proton-drive-*.rpm` (el10) |
| Debian 12 | `proton-drive_*.deb` (debian12) |
| Debian 13 | `proton-drive_*.deb` (debian13) |
| Ubuntu 24.04 / Mint 22.x | `proton-drive_*.deb` (ubuntu24.04) |
| Ubuntu 26.04 | `proton-drive_*.deb` (ubuntu26.04) |
| Arch / Manjaro / EndeavourOS / Garuda | `proton-drive-*.pkg.tar.zst` (AUR) or AppImage |
| Any Linux (portable) | `proton-drive_*.AppImage` |
| Flatpak (GNOME 49/50) | `proton-drive_*.flatpak` |
| Snap (core24) | `proton-drive_*.snap` (core24) |
| Snap (core26) | `proton-drive_*.snap` (core26) |

---

## Source of Truth

`packaging/compatibility-map.yml` is the machine-readable compatibility map. See that file for build targets, artifact names, release labels, and supported distro mappings.
