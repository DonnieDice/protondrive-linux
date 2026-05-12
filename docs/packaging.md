# Packaging

Packaging is intentionally split by distro/package type. Each package owns its workflow and patch directory, even when some build steps are similar.

## Package Ownership

| Package | Workflows | Patch Directory | Distro Patches | Notes |
|---------|-----------|-----------------|----------------|-------|
| RPM | `build-rpm.fedora.43.yml`, `build-rpm.fedora.44.yml`, `build-rpm.el9.yml`, `build-rpm.el10.yml` | `patches/rpm/` | `fedora.43.patch`, `fedora.44.patch`, `el9.patch`, `el10.patch` | Fedora and RHEL/EL family. F43/F44 share compat baseline (webkit2gtk 2.52+). EL9 uses older webkit2gtk 2.40; EL10 uses 2.52+. |
| DEB | `build-deb.yml`, `build-deb.debian.13.yml`, `build-deb.ubuntu.22.04.yml`, `build-deb.ubuntu.26.04.yml` | `patches/deb/` | `debian.12.patch`, `debian.13.patch`, `ubuntu.22.04.patch`, `ubuntu.24.04.patch`, `ubuntu.26.04.patch` | Debian/Ubuntu/Mint/Zorin/Pop!\_OS. `build-deb.yml` covers Debian 12 and Ubuntu 24.04 (default patch). |
| AppImage | `build-appimage.yml` | `patches/appimage/` | `linux-baseline.patch` | Single universal target; glibc 2.35+ baseline. |
| Flatpak | `build-flatpak.yml` | `patches/flatpak/` | `org.gnome.Platform.50.patch` | GNOME Platform 50 runtime Flatpak package. |
| Snap | `build-snap.yml`, `build-snap.core26.yml` | `patches/snap/` | `core24.patch`, `core26.patch` | core24 and core26 Snap packages. core26 includes webkit2gtk 2.52+ sandbox and IPInt fixes. |
| AUR | `build-aur.yml`, `publish-aur.yml` | `patches/aur/` | `arch.patch`, `arch.wrapper` | Full Tauri build + makepkg. Single `arch` target covers all Arch-family distros. |

## Design Standards

- Keep package workflows separate so one distro failure is easy to isolate.
- Keep distro-specific patches out of `patches/common/`.
- Use `patches/common/` only for changes required by all packages.
- **Base code (`src-tauri/src/main.rs`) must NOT contain distro-specific env vars or DISTRO_TYPE branching.** The base binary ships clean — zero distro-specific code. All WebKitGTK env vars, sandbox overrides, and renderer flags belong exclusively in `patches/<package>/<runtime>.patch`. If a distro-specific value appears in `main.rs`, it is a bug. The only acceptable content in `main.rs` for these settings is the placeholder comment: `// NOTE: WebKitGTK env vars are NOT set here. They are distro-specific and belong in patches.`
- **Patches are named by runtime/ABI target, not host distro.** AppImage/Flatpak/Snap patches target the runtime (e.g., `linux-baseline`, `org.gnome.Platform.50`, `core24`, `core26`). DEB/RPM patches remain distro-specific (e.g., `ubuntu.24.04.patch`, `fedora.43.patch`, `el9.patch`). AUR uses a single `arch` target covering all Arch-family distros.

## Distro Patch Convention

Patches are named by runtime/ABI target inside the package directory:

```
patches/
├── common/fix-tauri-worker-protocol.patch   # WebClients tauri:// worker protocol fix
├── appimage/linux-baseline.patch            # Linux baseline (glibc 2.35+): GDK_GL=software
├── aur/arch.patch                           # Arch-family (webkit2gtk 2.52+): GDK_GL=disable, sandbox+IPInt fixes
├── deb/debian.12.patch                      # Debian 12: GDK_GL=disable
├── deb/debian.13.patch                      # Debian 13: GDK_GL=software
├── deb/ubuntu.22.04.patch                   # Ubuntu 22.04: GDK_GL=disable
├── deb/ubuntu.24.04.patch                   # Ubuntu 24.04: GDK_GL=software
├── deb/ubuntu.26.04.patch                   # Ubuntu 26.04: GDK_GL=software
├── rpm/fedora.43.patch                      # Fedora 43: WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1, JSC_useWasmIPInt=false
├── rpm/fedora.44.patch                      # Fedora 44: same as fedora.43 (same compat baseline)
├── rpm/el9.patch                            # EL9: WEBKIT_FORCE_SANDBOX=0, GDK_GL=disable
├── rpm/el10.patch                           # EL10: WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1, JSC_useWasmIPInt=false
├── flatpak/org.gnome.Platform.50.patch      # GNOME Platform 50 runtime
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
- **EL9 (webkit2gtk 2.40):** `WEBKIT_FORCE_SANDBOX=0`; `GDK_GL=disable` + `LIBGL_ALWAYS_SOFTWARE=1`.
- **Ubuntu 24.04+/Debian 13+:** `GDK_GL=software` (NOT `GDK_GL=disable` — crashes WebKitWebProcess).
- **Ubuntu 22.04/Debian 12:** `GDK_GL=disable` + `LIBGL_ALWAYS_SOFTWARE=1`.
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

- `proton-drive-*.rpm` (fedora43, fedora44, el9, el10)
- `proton-drive_*.deb` (debian12, debian13, ubuntu22.04, ubuntu24.04, ubuntu26.04)
- `proton-drive_*.AppImage`
- `proton-drive_*.flatpak`
- `proton-drive_*_amd64.snap` (core24, core26)
- `proton-drive-*.pkg.tar.zst` (AUR)
- `SHA256SUMS`
