# Proton Drive Linux - CI/CD Workflows

## Quick Reference

### Status Badges

```markdown
![Build All Platforms](https://github.com/donniedice/protondrive-tauri/actions/workflows/build-all-platforms.yml/badge.svg)
![Build Flatpak](https://github.com/donniedice/protondrive-tauri/actions/workflows/build-flatpak.yml/badge.svg)
![Build Snap](https://github.com/donniedice/protondrive-tauri/actions/workflows/build-snap.yml/badge.svg)
![Publish Packages](https://github.com/donniedice/protondrive-tauri/actions/workflows/publish-packages.yml/badge.svg)
```

## Available Workflows

| Workflow | Triggers | Outputs | Duration |
|----------|----------|---------|----------|
| **build-all-platforms.yml** | push/tag/dispatch | Linux/macOS/Windows | 90 min |
| **build-flatpak.yml** | push/tag/dispatch | Flatpak bundle | 120 min |
| **build-snap.yml** | push/tag/dispatch | Snap package | 90 min |
| **build-linux-packages.yml** | push/tag/dispatch | DEB/RPM/AppImage | 90 min |
| **publish-packages.yml** | tag/dispatch | AUR/COPR/Source | 30 min |
| **release.yml** | tag | GitHub Release | 5 min |
| **web-build.yml** | push/PR | Web artifacts | 30 min |

## What Gets Built

### On Every Push (main/dev branches)
- ✅ Linux packages (DEB, RPM, AppImage)
- ✅ macOS packages (DMG, APP)
- ✅ Windows packages (MSI, NSIS)
- ✅ Flatpak bundle
- ✅ Snap package

### On Every Tag (v*)
- ✅ All above
- ✅ AUR PKGBUILD
- ✅ RPM spec file (COPR)
- ✅ Source distribution tarball
- ✅ GitHub Release with all artifacts

## Getting Started with CI/CD

### 1. Local Testing (Before Push)

```bash
# Build locally to verify
npm run build

# Or build specific packages
npm run build:linux
npm run build:rpm
npm run build:appimage
```

### 2. Push to Trigger Builds

```bash
# Push to main/dev branches
git push origin main

# Or create a release tag
git tag -a v1.0.1 -m "Release 1.0.1"
git push origin v1.0.1
```

### 3. Monitor Workflows

- Go to: `https://github.com/donniedice/protondrive-tauri/actions`
- Click workflow to see detailed logs
- Download artifacts from completed runs

### 4. Creating Releases

```bash
# Create and push a version tag
git tag -a v1.0.1 -m "Release 1.0.1"
git push origin v1.0.1

# This automatically:
# - Triggers all build workflows
# - Creates GitHub Release
# - Uploads all binaries
# - Generates checksums
```

## Workflow Details

### build-all-platforms.yml

**When it runs:**
- Every push to main/dev
- Every tag push (v*)
- Manual dispatch

**What it builds:**
- Linux: DEB, RPM, AppImage
- macOS: DMG, APP
- Windows: MSI, NSIS

**Time:** ~90 minutes per platform (parallel builds)

**Output Files:**
```
artifacts/
├── linux-builds/
│   ├── proton-drive_1.0.0_amd64.AppImage
│   ├── proton-drive_1.0.0_amd64.deb
│   └── proton-drive-1.0.0-1.x86_64.rpm
├── macos-builds/
│   ├── Proton Drive.dmg
│   └── Proton Drive.app/
└── windows-builds/
    ├── Proton Drive_1.0.0_x64_en-US.msi
    └── Proton Drive_1.0.0_x64-setup.exe
```

### build-flatpak.yml

**When it runs:**
- Every push to main/dev
- Every tag push (v*)
- Manual dispatch

**What it builds:**
- Self-contained Flatpak bundle

**Container:** Ubuntu with Flatpak builder

**Output Files:**
```
artifacts/
├── flatpak-bundle/
│   └── proton-drive.flatpak
└── flatpak-manifest/
    └── com.proton.drive.yml
```

**Installation:**
```bash
flatpak install ./proton-drive.flatpak
# Or submit to Flathub for app store distribution
```

### build-snap.yml

**When it runs:**
- Every push to main/dev
- Every tag push (v*)
- Manual dispatch

**What it builds:**
- Universal Snap package
- Supports x86_64 and ARM64

**Output Files:**
```
artifacts/
├── snap-package/
│   └── proton-drive_1.0.0_amd64.snap
└── snap-config/
    └── snapcraft.yaml
```

**Installation:**
```bash
snap install ./proton-drive_1.0.0_amd64.snap --dangerous
# Or publish to Snap Store
```

### publish-packages.yml

**When it runs:**
- Tag push (v*) only
- Manual dispatch

**What it generates:**
- AUR PKGBUILD file
- RPM spec file for COPR
- Source distribution tarball

**Output Files:**
```
artifacts/
├── aur-pkgbuild/
│   └── PKGBUILD
├── rpm-spec/
│   ├── proton-drive.spec
│   └── .copr/Makefile
└── source-distribution/
    ├── proton-drive-1.0.0.tar.gz
    └── proton-drive-1.0.0.tar.gz.sha256
```

**Next Steps:**
- Submit PKGBUILD to AUR
- Build RPM in COPR
- Host source tarball

### release.yml

**When it runs:**
- Tag push (v*) only

**What it does:**
- Creates GitHub Release
- Uploads build artifacts
- Generates release notes
- Calculates SHA256 checksums

**Access at:** https://github.com/donniedice/protondrive-tauri/releases

## Manual Trigger

To manually trigger any workflow:

1. Go to: `https://github.com/donniedice/protondrive-tauri/actions`
2. Select workflow
3. Click "Run workflow"
4. Choose branch and click "Run workflow"

## Checking Build Status

### In GitHub
```
Workflows → [Select Workflow] → Recent runs
```

### In Commit Details
Push → Commit will show status checks

### Badge for README
```markdown
[![Build Status](https://github.com/donniedice/protondrive-tauri/actions/workflows/build-all-platforms.yml/badge.svg?branch=main)](https://github.com/donniedice/protondrive-tauri/actions/workflows/build-all-platforms.yml)
```

## Common Tasks

### Build on Push to main

✅ Automated - happens automatically

### Build on PR

Only `web-build.yml` runs for fast feedback

### Create a Release

```bash
git tag -a v1.0.1 -m "Release version 1.0.1"
git push origin v1.0.1
# Wait ~5-10 minutes for all builds to complete
# GitHub Release will be created automatically
```

### Download Artifacts from CI

1. Go to workflow run
2. Scroll to "Artifacts" section
3. Click artifact to download (zip file)

### Submit to AUR

```bash
# After tag push, download PKGBUILD artifact
# Edit PKGBUILD with your info
cd ~/aur/proton-drive
# Replace files with new PKGBUILD
git add PKGBUILD
git commit -m "Update to vX.X.X"
git push
```

### Publish to Snap Store

```bash
# After snap build completes:
snapcraft login
snapcraft upload proton-drive_1.0.0_amd64.snap --release=stable
```

### Publish to Flathub

1. Fork https://github.com/flathub/com.proton.drive
2. Update manifest
3. Create PR to Flathub

## Troubleshooting

### Build Timeout

- Workflows have 90-120 minute timeout
- Check for stuck processes in logs
- May need to optimize build steps

### Out of Space Error

- GitHub runner has 14GB available
- Large WebClients checkout can use 2-3GB
- Clean build artifacts between jobs

### Python Unicode Error (Windows)

- Set `PYTHONIOENCODING: utf-8` in workflow (already done)
- Handles fix_deps.py compatibility

### Missing Artifacts

- Check "if-no-files-found: error" in workflow
- Verify build actually completed successfully
- Check build command output for errors

## Performance Tips

1. **Parallel Jobs** - Linux/macOS/Windows build simultaneously (~90 min total, not 270)
2. **Caching** - Rust and npm caches reduce dependency download time
3. **Shallow Clone** - WebClients uses `--depth=1` to speed up git clone
4. **Node Memory** - `NODE_OPTIONS="--max-old-space-size=8192"` prevents OOM

## Next Steps

See [CI_CD.md](CI_CD.md) for detailed documentation of all workflows, triggers, and configuration options.

## Support

- Check GitHub Actions logs for detailed error messages
- Review workflow YAML files in `.github/workflows/`
- See [CI_CD.md](CI_CD.md) for comprehensive guide
