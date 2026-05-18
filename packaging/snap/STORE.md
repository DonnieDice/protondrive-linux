# Snap Store Distribution

## Setup Steps

1. ~~Register the `proton-drive` snap name at https://snapcraft.io/register-snap~~ **Done**
2. Export Snap Store credentials: `snapcraft export-login --`
3. Add `SNAPCRAFT_STORE_CREDENTIALS` as a GitHub Actions secret
4. Add `publish-snap.yml` workflow to upload snaps on release
5. Test end-to-end: tag push → build → upload → `snap install proton-drive`

## Confinement

Using `confinement: strict` — no classic confinement request needed.

Current app capabilities:
- **Downloads**: Files go to `~/Downloads`, covered by the `home` plug
- **Uploads**: GTK file picker (Portal) already has access to home directory via `home` plug
- **Removable media**: `removable-media` plug added for USB/mounted drives at `/media`, `/mnt`, `/run/media`
- **Future 2-way sync**: Will need `system-files` plug or a classic confinement request at that point; not needed today

## Current State

- Snap builds exist for core24 and core26 (both release-gated)
- `packaging/snap/snapcraft.yaml` uses `confinement: strict` with `removable-media` plug
- Snap name `proton-drive` registered on the Snap Store
- No Snap Store publishing pipeline exists yet
