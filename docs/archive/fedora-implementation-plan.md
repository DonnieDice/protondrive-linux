# Proton Drive Linux - Worker Compatibility Implementation Plan

**Status:** Ready for Implementation
**Date:** 2025-12-29
**Issue:** System WebKitGTK doesn't support Web Workers from `tauri://` protocol

---

## Problem Statement

### The Core Issue
RPM/deb/Flatpak/Snap builds use **system WebKitGTK** which blocks Workers from `tauri://` protocol URLs with error: `"The operation is insecure"`.

AppImage/AUR work fine because they **bundle WebKitGTK** or use configurations that allow custom protocol Workers.

### Impact
- Login screen shows infinite spinner after entering credentials
- Login API calls succeed (AccessToken received) but UI never updates
- User cannot access their Proton Drive account

### Root Cause
Proton WebClients' webpack bundles call `new Worker()` without feature detection:
```javascript
// Minified code at public-index.2ae8d2f5.js:1003:87490
new Worker(new URL(r.p+r.u(1711),r.b))
```

When Worker fails, the error is unhandled and login flow hangs.

---

## Solution: Source Code Patching

### Why Patching?
We clone and build WebClients from **source code** specifically to avoid dealing with minified bundles. We can patch the source before building.

### The Built-in Fallback
Proton WebClients **already has** a non-Worker crypto mode! It's triggered by this check:

**File:** `packages/shared/lib/helpers/setupCryptoWorker.ts`
```typescript
const init = async (options?: CryptoWorkerOptions) => {
    const isWorker = typeof window === 'undefined' || typeof document === 'undefined';
    const isCompat = isWorker || !hasModulesSupport();

    // Compat browsers do not support the worker.
    if (isCompat) {
        // Load crypto API directly in main thread
        const { Api: CryptoApi } = await import(
            '@proton/crypto/lib/worker/api'
        );
        CryptoApi.init(options?.openpgpConfigOptions || {});
        CryptoProxy.setEndpoint(new CryptoApi(), (endpoint) => endpoint.clearKeyStore());
    } else {
        // Use Worker pool (default)
        await CryptoWorkerPool.init({...});
        CryptoProxy.setEndpoint(CryptoWorkerPool, (endpoint) => endpoint.destroy());
    }
};
```

**If `hasModulesSupport()` returns `false`, Proton loads crypto in main thread!**

---

## Implementation Steps

### Step 1: Create Patch File

**Location:** `patches/webclients/001-tauri-worker-compat.patch`

**Content:**
```diff
--- a/packages/shared/lib/helpers/browser.ts
+++ b/packages/shared/lib/helpers/browser.ts
@@ -6,6 +6,12 @@ const ua = uaParser.getResult();

 export const hasModulesSupport = () => {
+    // Detect Tauri environment
+    // System WebKitGTK (RPM/deb/flatpak) doesn't support Workers from tauri:// protocol
+    // Force non-Worker crypto mode to use main-thread fallback
+    if (typeof window !== 'undefined' && window.__TAURI__) {
+        return false;
+    }
+
     const script = document.createElement('script');
     return 'noModule' in script;
 };
```

### Step 2: Update Build Script

**File:** `scripts/build-webclients.sh`

**Add patch application after cloning:**
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WEBCLIENTS_DIR="$REPO_ROOT/WebClients"

# Clone or update WebClients
if [ ! -d "$WEBCLIENTS_DIR" ]; then
    echo "Cloning WebClients..."
    git clone https://github.com/ProtonMail/WebClients.git "$WEBCLIENTS_DIR"
    cd "$WEBCLIENTS_DIR"
    git checkout DRIVE@6.4.0
else
    echo "Using existing WebClients directory"
    cd "$WEBCLIENTS_DIR"
fi

# Apply patches
echo "Applying patches..."
PATCHES_DIR="$REPO_ROOT/patches/webclients"
if [ -d "$PATCHES_DIR" ]; then
    for patch in "$PATCHES_DIR"/*.patch; do
        if [ -f "$patch" ]; then
            echo "  Applying $(basename "$patch")..."
            # Check if already applied
            if git apply --check "$patch" 2>/dev/null; then
                git apply "$patch"
                echo "  ✓ Applied"
            else
                echo "  ⚠ Already applied or conflicts - skipping"
            fi
        fi
    done
fi

# Rest of build script...
python3 ../scripts/fix_deps.py
yarn install
yarn workspace proton-drive build:web
yarn workspace proton-account build:web
yarn workspace proton-verify build:web

# Copy to dist
# ... existing copy logic ...
```

### Step 3: Update Workflows

**All workflow files** (build-linux-packages.yml, build-deb.yml, build-rpm.yml, etc.)

**Add before build:**
```yaml
- name: Apply WebClients patches
  run: |
    cd WebClients
    if [ -d ../patches/webclients ]; then
      for patch in ../patches/webclients/*.patch; do
        if [ -f "$patch" ]; then
          echo "Applying $(basename "$patch")..."
          git apply --check "$patch" && git apply "$patch" || echo "Already applied"
        fi
      done
    fi
```

### Step 4: Verify Patch Works

**Test locally:**
```bash
# Clean build
rm -rf WebClients
./scripts/build-webclients.sh

# Verify patch was applied
cd WebClients
git diff packages/shared/lib/helpers/browser.ts

# Should show the Tauri detection code
```

**Test in app:**
```bash
cd src-tauri
DISTRO_TYPE=rpm cargo build --release
./target/release/proton-drive

# Login should work without Worker errors
```

---

## Architecture

### Before (Broken)
```
System WebKitGTK → new Worker(tauri://...) → "The operation is insecure" → CRASH
```

### After (Fixed)
```
Tauri Detection → hasModulesSupport() returns false → Proton loads crypto in main thread → LOGIN WORKS
```

---

## Distribution-Specific Behavior

### AppImage / AUR (No Changes Needed)
- Bundled or compatible WebKitGTK
- Workers work natively
- Patch check: `window.__TAURI__` exists but Workers work, so no issue

### RPM / deb / Flatpak / Snap (Patch Activates)
- System WebKitGTK
- Patch detects `window.__TAURI__`
- Forces `hasModulesSupport()` to return `false`
- Proton uses main-thread crypto mode

---

## File Changes Summary

### New Files
```
patches/
└── webclients/
    └── 001-tauri-worker-compat.patch
```

### Modified Files
```
scripts/build-webclients.sh          (add patch application)
.github/workflows/*.yml              (add patch step)
```

### Patched WebClients File
```
WebClients/packages/shared/lib/helpers/browser.ts
```

---

## Testing Checklist

- [ ] Create patch file
- [ ] Update build script to apply patches
- [ ] Test local build with patch
- [ ] Verify login works on Fedora RPM
- [ ] Update all GitHub workflows
- [ ] Test AppImage still works (Workers should still function)
- [ ] Test AUR build
- [ ] Test deb build
- [ ] Document in CHANGELOG.md

---

## Rollback Plan

If patch causes issues:
```bash
# Remove patch file
rm patches/webclients/001-tauri-worker-compat.patch

# Revert build script changes
git checkout scripts/build-webclients.sh

# Rebuild
rm -rf WebClients
./scripts/build-webclients.sh
```

---

## References

- **Proton Fallback Code:** `packages/shared/lib/helpers/setupCryptoWorker.ts:14-39`
- **Feature Detection:** `packages/shared/lib/helpers/browser.ts:7-10`
- **Worker Debugging Log:** `WORKER_DEBUGGING.md`
- **Historic Debugging:** `DEBUGGING.md` Session 7
