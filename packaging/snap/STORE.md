# Snap Store Distribution

This directory will contain Snap Store publishing configuration.

## Setup Steps

1. Register the `proton-drive` snap name at https://snapcraft.io/register-snap
2. Request classic confinement (if needed) at https://forum.snapcraft.io/c/process
3. Export Snap Store credentials: `snapcraft export-login --`
4. Add `SNAPCRAFT_STORE_CREDENTIALS` as a GitHub Actions secret
5. The `publish-snap.yml` workflow will upload snaps on release

## Current State

- Snap builds exist for core24 and core26 (both release-gated)
- `packaging/snap/snapcraft.yaml` uses `confinement: strict`
- No Snap Store publishing pipeline exists yet
