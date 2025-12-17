# Build Matrix - What Gets Built When

## Event Triggers

### 1. Push to main branch
```
Event: git push origin main
Trigger: Immediate
Workflows: ALL (except manual dispatch)
Duration: ~120 minutes
```

**Builds:**
- ✅ Linux: DEB, RPM, AppImage
- ✅ macOS: DMG, APP
- ✅ Windows: MSI, NSIS
- ✅ Flatpak bundle
- ✅ Snap package

**Outputs:**
- Available in Actions artifacts (30 day retention)
- No GitHub Release created
- Useful for testing/staging builds

---

### 2. Push to dev branch
```
Event: git push origin dev
Trigger: Immediate
Workflows: Same as main branch
Duration: ~120 minutes
```

**Builds:**
- All platforms and formats (same as main)
- Used for development/testing

**Outputs:**
- Available in Actions artifacts
- No GitHub Release

---

### 3. Create and push version tag
```
Event: git tag -a v1.0.0 && git push origin v1.0.0
Trigger: Immediate
Workflows: ALL
Duration: ~150 minutes
```

**Builds:**
- ✅ All platforms and formats (as above)
- ✅ AUR PKGBUILD
- ✅ RPM spec file (for COPR)
- ✅ Source distribution tarball
- ✅ GitHub Release

**Outputs:**
- All binaries in GitHub Release
- Checksums (SHA256) generated
- Release notes auto-generated
- Artifacts available for 90 days

**Manual Actions (Optional):**
- Submit PKGBUILD to AUR
- Build in COPR
- Upload to Snap Store
- Submit to Flathub

---

### 4. Manual Dispatch from Actions UI
```
Event: Click "Run workflow" in Actions tab
Trigger: Manual
Workflows: Selected workflow only
Duration: Varies by workflow (5-120 min)
```

**Options:**
- Choose specific workflow
- Select branch
- Useful for re-running or testing

**Note:** Does NOT create GitHub Release (only tag push does)

---

## Complete Build Matrix

```
┌─────────────────────┬──────────────┬────────────────────────────────────────────┐
│ Trigger Event       │ Duration     │ Builds Created                             │
├─────────────────────┼──────────────┼────────────────────────────────────────────┤
│ Push to main/dev    │ ~120 min     │ DEB, RPM, AppImage, DMG, APP,              │
│                     │              │ MSI, NSIS, Flatpak, Snap                   │
├─────────────────────┼──────────────┼────────────────────────────────────────────┤
│ Tag push (v*)       │ ~150 min     │ ↑ All above                                 │
│ + Release creation  │              │ + PKGBUILD (AUR)                           │
│                     │              │ + Spec file (COPR)                         │
│                     │              │ + Source tarball                           │
│                     │              │ + GitHub Release                           │
├─────────────────────┼──────────────┼────────────────────────────────────────────┤
│ Manual dispatch     │ 5-120 min    │ Selected workflow only                     │
├─────────────────────┼──────────────┼────────────────────────────────────────────┤
│ Pull request        │ ~30 min      │ Web build only (fast feedback)              │
│ to main/dev         │              │                                            │
└─────────────────────┴──────────────┴────────────────────────────────────────────┘
```

## Step-by-Step Release Process

### To Create a Release:

```bash
# Step 1: Make sure everything is committed
git status
# (should show "nothing to commit")

# Step 2: Create an annotated tag
git tag -a v1.0.0 -m "Release version 1.0.0"

# Step 3: Push the tag to GitHub
git push origin v1.0.0

# Step 4: Monitor the build
# Open: https://github.com/donniedice/protondrive-tauri/actions
# Watch workflows complete (takes ~150 minutes)

# Step 5: Find the release
# Open: https://github.com/donniedice/protondrive-tauri/releases
# Click on "v1.0.0" to download packages
```

### What Happens Automatically:

1. ✅ build-all-platforms.yml starts
   - Builds Linux (DEB/RPM/AppImage)
   - Builds macOS (DMG/APP)
   - Builds Windows (MSI/NSIS)
   - Takes ~90 minutes (parallel)

2. ✅ build-flatpak.yml starts
   - Builds Flatpak bundle
   - Takes ~120 minutes

3. ✅ build-snap.yml starts
   - Builds Snap package
   - Takes ~90 minutes

4. ✅ publish-packages.yml starts
   - Generates AUR PKGBUILD
   - Generates RPM spec (COPR)
   - Creates source tarball
   - Takes ~30 minutes

5. ✅ release.yml starts (after others complete)
   - Creates GitHub Release
   - Uploads all artifacts
   - Generates checksums
   - Takes ~5 minutes

## Output Locations

### Artifacts (Temporary - 30/90 days)
```
GitHub → Repository → Actions
→ [Workflow Run] → Artifacts
```

Files available:
- linux-builds: DEB, RPM, AppImage
- macos-builds: DMG, APP
- windows-builds: MSI, NSIS
- flatpak-bundle: .flatpak file
- snap-package: .snap file
- aur-pkgbuild: PKGBUILD
- rpm-spec: .spec file
- source-distribution: .tar.gz

### Releases (Permanent)
```
GitHub → Repository → Releases
→ [v1.0.0] → Download section
```

Files available:
- All binaries (DEB, RPM, AppImage, DMG, APP, MSI, NSIS)
- SHA256SUMS file
- Checksums verified

### Artifacts Retention Periods
- Standard builds: 30 days
- Release artifacts: 90 days
- GitHub Releases: Permanent

## Parallel Build Execution

### Build Timeline (Concurrent)
```
Time  | build-all-platforms | build-flatpak | build-snap
──────┼─────────────────────┼───────────────┼──────────
0 min │ ████████ Linux      │ █████ Setup   │ ████ Setup
      │
30 min│ ████████ macOS      │ ███████ Build │ ████████ Install
      │
60 min│ ████████ Windows    │ ███████ Build │ ████████ Build
      │ ████ prep-release   │               │
      │
90 min│ ▼ Complete          │               │ ▼ Complete
      │                     │
120min│                     │ ▼ Complete    │
      │
150min│ ← Total time ~150 minutes

Key: Parallel = overlapping execution = faster overall
```

## Package Details

### DEB (Debian/Ubuntu)
- **File:** proton-drive_1.0.0_amd64.deb
- **Workflow:** build-all-platforms
- **Install:** `sudo apt install ./proton-drive_1.0.0_amd64.deb`

### RPM (Fedora/RHEL/CentOS)
- **File:** proton-drive-1.0.0-1.x86_64.rpm
- **Workflow:** build-all-platforms
- **Install:** `sudo dnf install ./proton-drive-1.0.0-1.x86_64.rpm`

### AppImage (Generic Linux)
- **File:** proton-drive_1.0.0_amd64.AppImage
- **Workflow:** build-all-platforms
- **Install:** `chmod +x proton-drive_1.0.0_amd64.AppImage && ./proton-drive_1.0.0_amd64.AppImage`

### Flatpak (All Distributions)
- **File:** proton-drive.flatpak
- **Workflow:** build-flatpak
- **Install:** `flatpak install ./proton-drive.flatpak`
- **Status:** Ready for Flathub submission

### Snap (All Distributions)
- **File:** proton-drive_1.0.0_amd64.snap
- **Workflow:** build-snap
- **Install:** `snap install ./proton-drive_1.0.0_amd64.snap --dangerous`
- **Status:** Ready for Snap Store submission

### AUR (Arch Linux)
- **File:** PKGBUILD
- **Workflow:** publish-packages
- **Submit:** To AUR repository
- **Install:** `yay -S proton-drive`

### COPR (Fedora Community)
- **File:** proton-drive.spec
- **Workflow:** publish-packages
- **Build:** In COPR project
- **Install:** `sudo dnf copr enable owner/proton-drive && sudo dnf install proton-drive`

### Source Distribution
- **File:** proton-drive-1.0.0.tar.gz
- **Workflow:** publish-packages
- **Use:** Source-based distributions or custom builds

### macOS
- **Files:** Proton Drive.dmg, Proton Drive.app
- **Workflow:** build-all-platforms
- **Install:** Drag & drop or run DMG installer

### Windows
- **Files:** *.msi, *-setup.exe
- **Workflow:** build-all-platforms
- **Install:** Run installer executable

## Failure Scenarios

### If a workflow fails:
1. ❌ That specific build stops
2. ⚠️ Other workflows continue (parallel execution)
3. 📧 GitHub sends failure notification
4. 📝 Logs available in Actions tab
5. ✅ Retry available via manual dispatch

### If a tag push fails:
- GitHub Release is NOT created
- Artifacts still available in build workflow
- Can retry or create new tag version

## Status Checks

### Monitor builds in real-time:
```
URL: https://github.com/donniedice/protondrive-tauri/actions
```

Shows:
- All workflow runs
- Status (running, success, failure)
- Duration and timing
- Detailed logs for each job
- Artifact downloads

## Summary

- **Branch push** → Fast builds (30 day storage)
- **Tag push** → Full release (permanent + 90 day storage)
- **PR** → Web build only (fast feedback)
- **Manual** → On demand for any branch/workflow

All builds are **fully automated** with no manual intervention needed!
