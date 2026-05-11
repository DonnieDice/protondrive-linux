# Packaging

Packaging is intentionally split by distro/package type. Each package owns its workflow and patch directory, even when some build steps are similar.

## Package Ownership

| Package | Workflow | Patch Directory | Distro Patches | Notes |
|---------|----------|-----------------|----------------|-------|
| RPM | `.github/workflows/build-rpm.fedora.40.yml`, `.github/workflows/build-rpm.fedora.41.yml`, `.github/workflows/build-rpm.fedora.42.yml`, `.github/workflows/build-rpm.fedora.43.yml`, `.github/workflows/build-rpm.fedora.44.yml` | `patches/rpm/` | `fedora.40.patch`, `fedora.41.patch`, `fedora.42.patch`, `fedora.43.patch`, `fedora.44.patch` | Fedora/RHEL/openSUSE package path. F40/41 share compat baseline (webkit2gtk <2.52); F42/43/44 share compat baseline (webkit2gtk 2.52+). |
| DEB | `.github/workflows/build-deb.yml` | `patches/deb/` | `ubuntu.24.04.patch`, `debian.12.patch` | Debian/Ubuntu/Mint/Zorin package path. Ubuntu VM validation pending. |
| AppImage | `.github/workflows/build-appimage.yml` | `patches/appimage/` | `linux-baseline.patch` | Single universal target; glibc 2.35+ baseline. |
| Flatpak | `.github/workflows/build-flatpak.yml` | `patches/flatpak/` | `org.gnome.Platform.50.patch` | GNOME Platform 50 runtime Flatpak package. |
| Snap | `.github/workflows/build-snap.yml` | `patches/snap/` | `core24.patch` | core24 Snap package. |
| AUR | `.github/workflows/build-aur.yml` | `patches/aur/` | `arch.patch`, `arch.wrapper` | Full Tauri build + makepkg. Single `arch` target covers all Arch-family distros. |

## Design Standards

- Keep package workflows separate so one distro failure is easy to isolate.
- Keep distro-specific patches out of `patches/common/`.
- Use `patches/common/` only for changes required by all packages.
- **Base code (`src-tauri/src/main.rs`) must NOT contain distro-specific env vars or DISTRO_TYPE branching.** The base binary ships clean — zero distro-specific code. All WebKitGTK env vars, sandbox overrides, and renderer flags belong exclusively in `patches/<package>/<runtime>.patch`. If a distro-specific value appears in `main.rs`, it is a bug. The only acceptable content in `main.rs` for these settings is the placeholder comment: `// NOTE: WebKitGTK env vars are NOT set here. They are distro-specific and belong in patches.`
- **Patches are named by runtime/ABI target, not host distro.** AppImage/Flatpak/Snap patches target the runtime (e.g., `linux-baseline`, `org.gnome.Platform.50`, `core24`). DEB/RPM patches remain distro-specific (e.g., `ubuntu.24.04.patch`, `fedora.42.patch`). AUR uses a single `arch` target covering all Arch-family distros.

## Distro Patch Convention

Patches are named by runtime/ABI target inside the package directory:

```
patches/
├── appimage/linux-baseline.patch        # Linux baseline (glibc 2.35+): GDK_GL=software
├── aur/arch.patch                       # Arch-family (webkit2gtk 2.52+): GDK_GL=disable, sandbox+IPInt fixes
├── deb/ubuntu.24.04.patch              # Ubuntu DEB: GDK_GL=software
├── deb/debian.12.patch                  # Debian DEB: GDK_GL=disable
├── rpm/fedora.40.patch                  # Fedora 40: WEBKIT_FORCE_SANDBOX=0, GDK_GL=disable
├── rpm/fedora.41.patch                  # Fedora 41: same as fedora.40.patch (same compat baseline)
├── rpm/fedora.42.patch                  # Fedora 42: WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1, JSC_useWasmIPInt=false
├── rpm/fedora.43.patch                  # Fedora 43: same as fedora.42.patch (same compat baseline)
├── rpm/fedora.44.patch                  # Fedora 44: same as fedora.42.patch (same compat baseline)
├── flatpak/org.gnome.Platform.50.patch  # GNOME Platform 50 runtime
└── snap/core24.patch                    # Snap core24 base
```

- **AppImage/Flatpak/Snap**: patches target the runtime/ABI, not the host distro
- **DEB/RPM**: patches remain distro-specific (different build containers, different dep sets)
- **AUR**: single `arch` target covers all Arch-family distros (same webkit2gtk version)

CI workflows apply the matching patch via target name before `cargo build`.

Validated RPM compatibility currently includes:

- `fedora40-compat` RPM: local and remote CI builds pass; validated on Fedora 40 and Fedora 41 (login, CAPTCHA, 2FA, Drive launch). Confirmed broken on Fedora 42+ (missing webkit2gtk 2.52+ sandbox and IPInt WASM fixes).
- `fedora42-compat` RPM: local and remote CI builds pass; validated on Fedora 42, Fedora 43, and Fedora 44 (login, CAPTCHA, 2FA, Drive launch). All three share webkit2gtk 2.52.3 — same binary works across the range.

## Required Runtime Fixes

The current Tauri/WebKitGTK app requires:

- WebKitGTK 4.1 dependencies.
- `WEBKIT_DISABLE_DMABUF_RENDERER=1` (all distros).
- `WEBKIT_DISABLE_COMPOSITING_MODE=1` (all distros).
- **Fedora 42+ (webkit2gtk 2.52+):** `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` replaces `WEBKIT_FORCE_SANDBOX=0`; `JSC_useWasmIPInt=false` disables the IPInt WASM interpreter (regression that causes SIGTRAP in WASM during post-2FA crypto).
- **Ubuntu 24.04+:** `GDK_GL=software` (NOT `GDK_GL=disable` — crashes WebKitWebProcess).
- **Debian/Fedora/others:** `GDK_GL=disable` + `LIBGL_ALWAYS_SOFTWARE=1`.
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

- `proton-drive-*.rpm`
- `proton-drive_*.deb`
- `proton-drive_*.AppImage`
- `SHA256SUMS`

AUR uses the AppImage release asset as its source package input.
