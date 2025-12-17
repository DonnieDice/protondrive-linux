# Release Guide

## How to Release a New Version

### 1. Create and Push a Version Tag

```bash
git tag v1.0.0
git push origin v1.0.0
```

Replace `v1.0.0` with your actual version number.

### 2. GitHub Actions Automatically:

1. **Builds** the app for:
   - Linux (AppImage, DEB, RPM)
   - macOS (.app, .dmg)
   - Windows (.exe, .msi)

2. **Creates** a GitHub Release with:
   - All precompiled binaries
   - SHA256 checksums (for security verification)
   - Auto-generated release notes from commit history

### 3. Users Can Install

**One-liner installs:**

```bash
# Linux AppImage
curl -sL https://github.com/donniedice/protondrive-tauri/releases/download/v1.0.0/Proton_Drive.AppImage -o ~/Downloads/ProtonDrive.AppImage && chmod +x ~/Downloads/ProtonDrive.AppImage && ~/Downloads/ProtonDrive.AppImage

# Ubuntu/Debian
sudo apt install https://github.com/donniedice/protondrive-tauri/releases/download/v1.0.0/proton-drive.deb

# Fedora/RHEL
sudo dnf install https://github.com/donniedice/protondrive-tauri/releases/download/v1.0.0/proton-drive.rpm

# macOS
curl -sL https://github.com/donniedice/protondrive-tauri/releases/download/v1.0.0/Proton_Drive.dmg -o ~/Downloads/ProtonDrive.dmg && open ~/Downloads/ProtonDrive.dmg
```

### Example Release Flow

```bash
# 1. Make changes to code
git commit -m "Add new feature"

# 2. Tag the release
git tag v1.0.1
git push origin v1.0.1

# 3. Watch GitHub Actions build
# Go to: https://github.com/donniedice/protondrive-tauri/actions

# 4. Release is automatically published to:
# https://github.com/donniedice/protondrive-tauri/releases/tag/v1.0.1

# 5. Users download and install with one-liner commands
```

## Versioning

Use [Semantic Versioning](https://semver.org/):

- `v1.0.0` - Initial release
- `v1.0.1` - Bug fix
- `v1.1.0` - New feature
- `v2.0.0` - Breaking change

## Updating WebClients (Proton Drive)

When Proton Drive releases a new version, update the submodule:

```bash
cd WebClients
git fetch origin
git checkout v<version>  # or a specific commit
cd ..
git add WebClients
git commit -m "Update WebClients to v<version>"
git tag v1.x.x
git push origin main --tags
```

## Verify Release Artifacts

After a release is created, verify the binaries:

```bash
# Download and check SHA256
curl -sL https://github.com/donniedice/protondrive-tauri/releases/download/v1.0.0/SHA256SUMS -o SHA256SUMS

# Verify files (Linux/macOS)
sha256sum -c SHA256SUMS

# Or manually
sha256sum Proton_Drive.AppImage
sha256sum proton-drive.deb
sha256sum proton-drive.rpm
```

## Notes

- First release may take 30-60 minutes to build
- Subsequent releases are typically 15-30 minutes
- All builds run in parallel (Linux, macOS, Windows)
- Release notes are auto-generated from git commit history
- Checksums allow users to verify integrity of downloaded files
