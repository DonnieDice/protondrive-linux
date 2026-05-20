# Snap Store Distribution

## Setup Steps

1. ~~Register the `proton-drive` snap name at https://snapcraft.io/register-snap~~ **Done**
2. Export Snap Store credentials: `snapcraft export-login -`
3. Add `SNAPCRAFT_STORE_CREDENTIALS` as a GitHub Actions secret
4. Add `publish-snap.yml` workflow to upload snaps on release
5. Test end-to-end: tag push → build → upload → `snap install proton-drive`

## Confinement

Using `confinement: strict` — no classic confinement request needed.

The app does not currently use a file picker. Downloads are handled by the
Rust `save_download` command and the Tauri `on_download` handler, both of
which write to `~/Downloads` via the `dirs` crate. This path is covered by
the `home` plug under strict confinement.

Snap plugs and what they cover:

| Plug | Path access | App feature |
|------|-------------|-------------|
| `home` | Non-hidden files in `$HOME` | `save_download` writes to `~/Downloads` |
| `removable-media` | `/media`, `/mnt`, `/run/media` | Future: downloads to or uploads from USB/mounted drives |
| `network` | Outbound network | API proxy, captcha, Proton endpoints |
| `desktop`, `x11`, `wayland` | Display server | Window rendering via WebKitGTK |
| `opengl` | GPU | Software rendering fallback (Mesa) |
| `browser-support` | WebKit subprocess | WebKitWebProcess, WebKitNetworkProcess |
| `password-manager-service` | Secret service | Proton credential storage |

When a file picker is added later (via `tauri-plugin-dialog`, which is already
registered in `main.rs`), it will use Tauri's dialog API. On Linux with
WebKitGTK, Tauri's dialog plugin invokes GTK's `GtkFileChooserNative` which
runs inside the snap and respects the same confinement rules — the `home` plug
will allow browsing `~/` and `removable-media` will allow browsing mounted
drives. No additional Snap-specific configuration is needed for the file picker
under strict confinement.

For future 2-way sync that writes to arbitrary directories outside `$HOME`,
a `system-files` plug or a classic confinement request will be needed at that
point. That is not required today.

## Snap Patches

- `patches/snap/core24.patch` — adds `DISTRO_TYPE=snap` to the worker init
  match arm, changes log label to "Snap/System package build"
- `patches/snap/core26.patch` — same as core24 plus `GDK_GL=disable`
  (instead of `software`) in the snapcraft.yaml environment

Both patches are applied by `build-snap.yml` and `build-snap.core26.yml`
respectively. No patch changes are needed for Snap Store publishing.

## Current State

- Snap builds exist for core24 and core26 (both release-gated)
- `packaging/snap/snapcraft.yaml` uses `confinement: strict` with
  `removable-media` plug
- Snap name `proton-drive` registered on the Snap Store
- Snap Store publishing pipeline: `publish-snap.yml` uploads snaps on
  release using `SNAPCRAFT_STORE_CREDENTIALS` secret
<<<<<<< HEAD
- End-to-end test (tag push -> build -> upload -> `snap install
  proton-drive`) is tracked in issue #83
=======
- **BLOCKED**: `snapcraft upload` returns `resource-not-found: Snap not
  found for name=proton-drive` despite the name being registered.
  `snapcraft register` also fails with `reserved_name`. `snapcraft names`
  shows no registered snaps even after successful registration. This
  appears to be a snapcraft CLI / Snap Store API inconsistency — the
  name reservation does not propagate to the upload endpoint. Publishing
  is on hold until this is resolved. See issues #83 and #19.
>>>>>>> 2b4513fbee12f24786e774b4232ce1f7b8579bc0
