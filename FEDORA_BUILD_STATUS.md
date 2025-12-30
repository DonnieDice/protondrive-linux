# Fedora Build Status - v1.1.2 (In Progress)

## 🚧 Current Work: Worker Compatibility Fix

### Issue
System WebKitGTK on Fedora/RPM/deb builds doesn't support Web Workers from `tauri://` protocol.

**Error:** `"The operation is insecure"` when creating Workers

**Impact:** Login hangs with infinite spinner - users cannot access their accounts

### Root Cause
- AppImage: Bundles WebKitGTK → Workers work ✅
- RPM/deb/Flatpak/Snap: Uses system WebKitGTK → Workers blocked ❌

### Solution: Source Code Patching
We're implementing a **patch system** to modify Proton WebClients source before building.

**Patch:** Force `hasModulesSupport()` to return `false` when running in Tauri, triggering Proton's built-in non-Worker crypto mode.

**See:** `IMPLEMENTATION_PLAN.md` for full details

---

## ✅ Verified Working (v1.1.1)

### Architecture
- ✅ Tauri 2.0 wrapper around Proton WebClients
- ✅ Rust HTTP proxy for API calls (CORS bypass)
- ✅ Account app integration for SSO login
- ✅ Verify app integration for CAPTCHA
- ✅ Cookie management via reqwest cookie jar
- ✅ Downloads to ~/Downloads via Tauri dialog
- ✅ Navigation intercept for proper app routing

### Build System

#### Local Build Script (`scripts/build-webclients.sh`)
- Clones/reuses WebClients repository
- Patches dependencies with `scripts/fix_deps.py`
- Installs WebClients dependencies
- Builds proton-drive, proton-account, proton-verify apps
- Copies account/verify to drive dist with path fixes
- **New:** Will apply patches from `patches/webclients/`

#### GitHub Workflows
All three package workflows:
1. `build-linux-packages.yml` - DEB, RPM, AppImage
2. `build-flatpak.yml` - Flatpak
3. `build-snap.yml` - Snap

**Current features:**
- Clone WebClients fresh every build
- Patch dependencies
- Build all three apps (drive, account, verify)
- Apply sed path fixes for nested deployment
- **TODO:** Add patch application step

### DISTRO_TYPE System
Implemented compile-time environment variable to differentiate builds:
- `DISTRO_TYPE=appimage` - Bundled WebKitGTK (Workers work)
- `DISTRO_TYPE=rpm` - System WebKitGTK (needs Worker workaround)
- `DISTRO_TYPE=deb` - System WebKitGTK (needs Worker workaround)
- `DISTRO_TYPE=flatpak` - Sandboxed (needs Worker workaround)
- `DISTRO_TYPE=snap` - Sandboxed (needs Worker workaround)

**Usage in Rust:**
```rust
match option_env!("DISTRO_TYPE") {
    Some("appimage") | Some("aur") => {
        // Native Workers supported
    }
    Some("rpm") | Some("deb") | Some("flatpak") | Some("snap") | None => {
        // Worker workaround needed
    }
}
```

---

## 📝 Implementation Roadmap

### Phase 1: Patch System ⏳
- [ ] Create `patches/webclients/001-tauri-worker-compat.patch`
- [ ] Update `scripts/build-webclients.sh` to apply patches
- [ ] Test local build on Fedora
- [ ] Verify login works without Worker errors

### Phase 2: Workflow Updates ⏳
- [ ] Add patch step to `build-linux-packages.yml`
- [ ] Add patch step to `build-deb.yml`
- [ ] Add patch step to `build-rpm.yml`
- [ ] Add patch step to `build-flatpak.yml`
- [ ] Add patch step to `build-snap.yml`

### Phase 3: Testing ⏳
- [ ] Test AppImage (should still use native Workers)
- [ ] Test AUR (should still use native Workers)
- [ ] Test RPM on Fedora (should use main-thread crypto)
- [ ] Test deb on Ubuntu/Debian (should use main-thread crypto)
- [ ] Test Flatpak
- [ ] Test Snap

### Phase 4: Release ⏳
- [ ] Update CHANGELOG.md
- [ ] Tag v1.1.2
- [ ] Build and publish all packages
- [ ] Update release notes

---

## 🔍 Debugging Resources

### Documentation
- `IMPLEMENTATION_PLAN.md` - Complete solution plan
- `WORKER_DEBUGGING.md` - All approaches attempted
- `DEBUGGING.md` - Full debugging history
- `CLAUDE.md` - Instructions for AI assistant

### Key Discoveries
1. **Proton has built-in fallback** - No Workers needed if `hasModulesSupport()` returns false
2. **Webpack bundles lack feature detection** - Calls `new Worker()` without checking support
3. **Tauri detection** - `window.__TAURI__` exists in all our builds
4. **Source patching** - Clean solution since we build from source

---

## 🐛 Known Issues

### RPM/deb Login (Current)
**Status:** Fix in progress
**Issue:** Infinite spinner on login
**Cause:** Worker creation fails, crypto library hangs
**Fix:** Source code patch to force non-Worker mode

### hCaptcha Challenges
**Status:** Working
**Solution:** Embedded verify app with iframe for captcha widget

---

## 📊 Build Matrix

| Package | WebKitGTK | Workers | Status | Notes |
|---------|-----------|---------|--------|-------|
| AppImage | Bundled | ✅ Native | ✅ Working | No patch needed |
| AUR | System | ✅ Native | ✅ Working | Arch config allows |
| RPM | System | ❌ Blocked | 🚧 Fixing | Needs patch |
| deb | System | ❌ Blocked | 🚧 Fixing | Needs patch |
| Flatpak | Sandboxed | ❌ Blocked | 🚧 Fixing | Needs patch |
| Snap | Sandboxed | ❌ Blocked | 🚧 Fixing | Needs patch |

---

## 🎯 Next Actions

1. **Implement patch file** - See `IMPLEMENTATION_PLAN.md` Step 1
2. **Update build script** - See `IMPLEMENTATION_PLAN.md` Step 2
3. **Test locally** - Verify login works on Fedora RPM
4. **Update workflows** - Add patch application to all workflows
5. **Test all distros** - Ensure no regressions

---

## 📅 Timeline

- **2025-12-29:** Worker issue identified, patch system designed
- **Next:** Implement patch and test
- **Target:** v1.1.2 release with full distro support
