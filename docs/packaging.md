# Packaging

Packaging is intentionally split by distro/package type. Each package owns its workflow and patch directory, even when some build steps are similar.

## Package Ownership

| Package | Workflows | Patch Directory | Distro Patches | Notes |
|---------|-----------|-----------------|----------------|-------|
| RPM | `build-rpm.fedora.43.yml`, `build-rpm.fedora.44.yml`, `build-rpm.el10.yml` | `patches/rpm/` | `fedora.43.patch`, `fedora.44.patch`, `el10.patch` | Fedora and RHEL/EL family. F43/F44 share compat baseline (webkit2gtk 2.52+). EL10 uses 2.52+. EL9 is not a current native RPM target because its GLib is too old for the current Tauri/GTK stack. |
| DEB | `build-deb.yml`, `build-deb.debian.13.yml`, `build-deb.ubuntu.24.04.yml`, `build-deb.ubuntu.26.04.yml` | `patches/deb/` | `debian.12.patch`, `debian.13.patch`, `ubuntu.24.04.patch`, `ubuntu.26.04.patch` | Debian/Ubuntu/Mint/Zorin/Pop!\_OS. `build-deb.yml` is the Debian 12 workflow. |
| AppImage | `build-appimage.yml` | `patches/appimage/` | `linux-baseline.patch` | Single universal target; glibc 2.35+ baseline, `JSC_useWasmIPInt=false`. |
| Flatpak | `build-flatpak.gnome49.yml`, `build-flatpak.yml` | `patches/flatpak/` | `org.gnome.Platform.49.patch`, `org.gnome.Platform.50.patch` | GNOME Platform 49 and 50 Flatpak runtimes. Both require `JSC_useWasmIPInt=false` for the post-2FA WebKit/JSC path. |
| Snap | `build-snap.yml`, `build-snap.core26.yml` | `patches/snap/` | `core24.patch`, `core26.patch` | core24 and core26 Snap packages. core26 includes webkit2gtk 2.52+ sandbox and IPInt fixes. |
| AUR | `build-aur.yml`, `publish-aur.yml` | `patches/aur/` | `arch.patch`, `arch.wrapper` | Full Tauri build + makepkg. Single `arch` target covers all Arch-family distros. |

## Design Standards

- Keep package workflows separate so one distro failure is easy to isolate.
- Keep distro-specific patches out of `patches/common/`.
- Use `patches/common/` only for changes required by all packages.
- **Base code (`src-tauri/src/main.rs`) must NOT contain distro-specific env vars or DISTRO_TYPE branching.** The base binary ships clean — zero distro-specific code. All WebKitGTK env vars, sandbox overrides, and renderer flags belong exclusively in `patches/<package>/<runtime>.patch`. If a distro-specific value appears in `main.rs`, it is a bug. The only acceptable content in `main.rs` for these settings is the placeholder comment: `// NOTE: WebKitGTK env vars are NOT set here. They are distro-specific and belong in patches.`
- **Patches are named by runtime/ABI target, not host distro.** AppImage/Flatpak/Snap patches target the runtime (e.g., `linux-baseline`, `org.gnome.Platform.49`, `org.gnome.Platform.50`, `core24`, `core26`). DEB/RPM patches remain distro-specific (e.g., `ubuntu.24.04.patch`, `fedora.43.patch`, `el10.patch`). AUR uses a single `arch` target covering all Arch-family distros.
- **DEB/RPM smoke tests must run on the matching target distro release.** Building a Debian 12 DEB on Ubuntu 26.04 can catch compile errors, but it does not validate the Debian 12 package. Runtime passes are only counted on the intended target host.

## Distro Patch Convention

Patches are named by runtime/ABI target inside the package directory:

```
patches/
├── common/fix-tauri-worker-protocol.patch   # WebClients tauri:// worker protocol fix
├── appimage/linux-baseline.patch            # Linux baseline (glibc 2.35+): GDK_GL=software, JSC_useWasmIPInt=false
├── aur/arch.patch                           # Arch-family (webkit2gtk 2.52+): GDK_GL=disable, sandbox+IPInt fixes
├── deb/debian.12.patch                      # Debian 12: GDK_GL=disable
├── deb/debian.13.patch                      # Debian 13: GDK_GL=software
├── deb/ubuntu.24.04.patch                   # Ubuntu 24.04: GDK_GL=software, JSC_useWasmIPInt=false
├── deb/ubuntu.26.04.patch                   # Ubuntu 26.04: GDK_GL=software, JSC_useWasmIPInt=false
├── rpm/fedora.43.patch                      # Fedora 43: WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1, JSC_useWasmIPInt=false
├── rpm/fedora.44.patch                      # Fedora 44: same as fedora.43 (same compat baseline)
├── rpm/el10.patch                           # EL10: WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1, JSC_useWasmIPInt=false
├── flatpak/org.gnome.Platform.49.patch      # GNOME Platform 49 runtime, JSC_useWasmIPInt=false
├── flatpak/org.gnome.Platform.50.patch      # GNOME Platform 50 runtime, JSC_useWasmIPInt=false
├── snap/core24.patch                        # Snap core24 base
└── snap/core26.patch                        # Snap core26 base (webkit2gtk 2.52+)
```

- **AppImage/Flatpak/Snap**: patches target the runtime/ABI, not the host distro
- **DEB/RPM**: patches remain distro-specific (different build containers, different dep sets)
- **AUR**: single `arch` target covers all Arch-family distros (same webkit2gtk version)

CI workflows apply the matching patch via target name before `cargo build`.

## Required Runtime Fixes

The current Tauri/WebKitGTK app requires:

- WebKitGTK 4.1 dependencies.
- `WEBKIT_DISABLE_DMABUF_RENDERER=1` (all distros).
- `WEBKIT_DISABLE_COMPOSITING_MODE=1` (all distros).
- **Fedora 43+/EL10 (webkit2gtk 2.52+):** `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`; `JSC_useWasmIPInt=false` disables the IPInt WASM interpreter (regression that causes SIGTRAP in WASM during post-2FA crypto).
- **Flatpak GNOME 49/50:** `JSC_useWasmIPInt=false` to avoid the post-2FA WebKit/JSC trap path seen in the login handoff.
- **Ubuntu 24.04+/Debian 13+:** `GDK_GL=software` plus `LIBGL_ALWAYS_SOFTWARE=1` (NOT `GDK_GL=disable` — crashes WebKitWebProcess). Ubuntu 24.04/26.04 also need `JSC_useWasmIPInt=false` to avoid the post-2FA WebKit/JSC trap path.
- **Debian 12:** `GDK_GL=disable` + `LIBGL_ALWAYS_SOFTWARE=1`.
- Account and Verify nested asset path fixes.
- Webpack SRI disabled at build time for Drive, Account, and Verify.

## DISTRO_TYPE

Each build sets the `DISTRO_TYPE` env var at compile time so Rust code can use `option_env!("DISTRO_TYPE")` for package-specific behavior:

| DISTRO_TYPE | Used by | Worker behavior |
|-------------|---------|-----------------|
| `appimage` | AppImage | Native Workers (bundled WebKitGTK) |
| `deb` | DEB | Main-thread crypto (system WebKitGTK) |
| `rpm` | RPM | Main-thread crypto (system WebKitGTK) |
| `flatpak` | Flatpak | Main-thread crypto (sandboxed WebKitGTK) |
| `snap` | Snap | Main-thread crypto (sandboxed WebKitGTK) |

## Artifacts

Required release artifacts:

- `proton-drive-*.rpm` (fedora43, fedora44, el10)
- `proton-drive_*_debian12_amd64.deb`
- `proton-drive_*_debian13_amd64.deb`
- `proton-drive_*_ubuntu24.04_amd64.deb`
- `proton-drive_*_ubuntu26.04_amd64.deb`
- `proton-drive_*.AppImage`
- `proton-drive_*.flatpak`
- `proton-drive_*_core24_amd64.snap`
- `proton-drive_*_core26_amd64.snap`
- `proton-drive-*.pkg.tar.zst` (AUR)
- `SHA256SUMS`
