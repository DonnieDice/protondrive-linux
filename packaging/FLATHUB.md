# Flathub Distribution

## Setup Steps

1. ~~Prepare the Flathub-ready manifest (`packaging/com.proton.drive.yml`)~~ **Done**
2. ~~Prepare the AppStream metainfo (`packaging/com.proton.drive.metainfo.xml`)~~ **Done**
3. Build and test the Flatpak locally:
   ```bash
   flatpak install -y flathub org.flatpak.Builder
   flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
   flatpak run --command=flatpak-builder org.flatpak.Builder --install --force-clean _build packaging/com.proton.drive.yml
   flatpak run com.proton.drive
   ```
4. Run the linter:
   ```bash
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest packaging/com.proton.drive.yml
   ```
5. Fork `flathub/flathub` on GitHub (copy the master branch only: unchecked)
6. Create a submission branch from `new-pr`:
   ```bash
   git clone --branch=new-pr git@github.com:YOUR_GITHUB_USERNAME/flathub.git && cd flathub
   git checkout -b proton-drive-submission new-pr
   ```
7. Add the manifest, metainfo, and desktop file, then push and open a PR
   against the `new-pr` base branch. Title: "Add com.proton.drive"
8. Address reviewer feedback, then request a test build with `bot, build`
9. After approval, the repo will be created at `flathub/com.proton.drive`
10. Accept the write access invitation (enable 2FA on GitHub first)
11. Add `FLATHUB_SSH_PRIVATE_KEY` as a GitHub Actions secret in the
    protondrive-linux repo
12. The `flatpak/publish` workflow will then push updates to the
 Flathub repo on each release

## Flathub Requirements

- App ID: `com.proton.drive` (follows reverse-DNS convention)
- License: AGPL-3.0 (approved by Flathub)
- Source-build manifest (not a binary download) — `packaging/com.proton.drive.yml`
  builds from the Git source with SDK extensions for Node.js and Rust
- AppStream metainfo with screenshots, description, and release history
- Desktop entry file with correct Icon ID (`com.proton.drive`)

## finish-args Rationale

| Permission | Reason |
|-----------|--------|
| `--share=network` | API proxy, captcha, Proton endpoints |
| `--share=ipc` | X11 shared memory |
| `--socket=fallback-x11` | X11 display (fallback, Wayland preferred) |
| `--socket=wayland` | Wayland display |
| `--socket=pulseaudio` | Audio playback for notifications |
| `--device=dri` | GPU rendering |
| `--filesystem=xdg-download` | Save downloaded files |
| `--filesystem=xdg-documents` | Future file sync access |
| `--talk-name=org.freedesktop.secrets` | Proton credential storage |
| `--talk-name=org.freedesktop.Notifications` | Desktop notifications |

## Runtime Settings

The Flatpak wrapper sets these environment variables:

- `WEBKIT_DISABLE_DMABUF_RENDERER=1` — avoid DMABUF rendering issues
- `WEBKIT_DISABLE_COMPOSITING_MODE=1` — disable GPU compositing
- `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` — disable WebKit subprocess
  sandbox (required for Flatpak WebKitGTK)
- `GDK_GL=disable` (GNOME 50) or `GDK_GL=software` (GNOME 49) — GL rendering
  mode
- `GSK_RENDERER=cairo` — use Cairo for rendering

## Current State

- Flatpak builds exist for GNOME 49 and GNOME 50 (both release-gated)
- Reference source-build manifest: `packaging/com.proton.drive.yml`
- CI build manifests (pre-built binary approach) in `build-flatpak.yml` and
  `build-flatpak.gnome49.yml`
- Flathub publishing pipeline: `flatpak/publish` pushes manifest updates
  to `flathub/com.proton.drive` on release using `FLATHUB_SSH_PRIVATE_KEY`
  secret
- Initial Flathub submission PR is required before the publish workflow can
  push updates
