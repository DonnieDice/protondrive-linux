# Web Worker Debugging Log - RPM/deb Build Issues

## Problem Statement
System WebKitGTK on RPM/deb builds doesn't support Workers loaded from `tauri://` protocol URLs, causing login to fail with infinite spinner.

**Error:** `The operation is insecure` when trying to create Workers from `tauri://` URLs

**Root Cause:** System WebKitGTK (used by RPM/deb) has security restrictions that prevent Workers from `tauri://` protocol, but bundled WebKitGTK (AppImage) works fine.

## Proton WebClients Architecture Discovery

**Key Finding:** Proton WebClients has built-in Worker fallback mode!

**Reference:** `WebClients/packages/shared/lib/helpers/setupCryptoWorker.ts`

```typescript
const init = async (options?: CryptoWorkerOptions) => {
    const isWorker = typeof window === 'undefined' || typeof document === 'undefined';
    const isCompat = isWorker || !hasModulesSupport();

    // Compat browsers do not support the worker.
    if (isCompat) {
        // dynamic import needed to avoid loading openpgp into the main thread
        const { Api: CryptoApi } = await import(
            /* webpackChunkName: "crypto-worker-api" */ '@proton/crypto/lib/worker/api'
        );
        CryptoApi.init(options?.openpgpConfigOptions || {});
        CryptoProxy.setEndpoint(new CryptoApi(), (endpoint) => endpoint.clearKeyStore());
    } else {
        await CryptoWorkerPool.init({...});
        CryptoProxy.setEndpoint(CryptoWorkerPool, (endpoint) => endpoint.destroy());
    }
};
```

**Fallback Trigger:** When `hasModulesSupport()` returns `false`, Proton loads crypto directly in main thread.

---

## Approaches Attempted

### ❌ Approach 1: Worker Throws Immediately
**Strategy:** Override `Worker` constructor to throw synchronously, forcing crypto library to detect failure and use sync fallback.

**Implementation:**
```javascript
window.Worker = function Worker(url) {
    const error = new Error('Worker not supported in WebKitGTK');
    error.name = 'SecurityError';
    throw error;
};
```

**Result:** FAILED
- Error: `[JS] [UNHANDLED] Worker not supported in WebKitGTK`
- Login stuck in infinite spinner
- Test logs: b35d66a, bf02330
- **Issue:** Crypto library doesn't use try-catch during Worker construction

---

### ❌ Approach 2: Worker Stub with onerror Callback
**Strategy:** Return stub that fires `onerror` event when `postMessage` is called, allowing crypto library to handle error asynchronously.

**Implementation:**
```javascript
window.Worker = function Worker(scriptURL, options) {
    const stub = {
        onmessage: null,
        onerror: null,
        postMessage: function(data, transfer) {
            setTimeout(() => {
                if (stub.onerror) {
                    const err = new Error('Worker not supported in WebKitGTK');
                    stub.onerror({ type: 'error', message: err.message, error: err });
                }
            }, 0);
        },
        // ... other stub methods
    };
    return stub;
};
```

**Result:** FAILED
- No UNHANDLED errors (good!)
- But login still stuck in infinite spinner
- Test logs: b818e6c
- **Issue:** Crypto library doesn't set up error handlers before calling postMessage

---

### ❌ Approach 3: Fetch Worker Script and Convert to Blob URL
**Strategy:** Intercept Worker creation, fetch the script content, and create a real Worker with blob: URL.

**Implementation:**
```javascript
window.Worker = function Worker(scriptURL, options) {
    let url = scriptURL;

    // Normalize tauri://account/... -> tauri://localhost/account/...
    if (url.startsWith('tauri://') && !url.startsWith('tauri://localhost/')) {
        url = url.replace(/^tauri:\/\//, 'tauri://localhost/');
    }

    fetch(url).then(response => response.text()).then(code => {
        const blob = new Blob([code], { type: 'application/javascript' });
        const blobURL = URL.createObjectURL(blob);
        realWorker = new OrigWorker(blobURL, options);
        // ... queue and process messages
    });
};
```

**Result:** FAILED (initially)
- Error: `SyntaxError: Unexpected token '<'`
- Test logs: b154bd1 (before normalization)
- **Issue:** Worker URL was `tauri://account/...` (missing localhost), fetched HTML error page instead of JS

**Result after URL normalization:** STILL FAILED
- Worker script loaded successfully (375KB)
- But login still stuck in infinite spinner
- Test logs: b63ec24
- **Issue:** Worker loads but doesn't respond - possibly importScripts() issues or same tauri:// protocol restrictions inside Worker context

---

### ❌ Approach 4: Echo Worker (Stub Returns Messages Immediately)
**Strategy:** Return functional stub that echoes messages back synchronously to prevent UI from hanging.

**Implementation:**
```javascript
window.Worker = function Worker(scriptURL, options) {
    const worker = {
        onmessage: null,
        postMessage: function(data, transfer) {
            setTimeout(() => {
                const event = { data: data, type: 'message', target: worker };
                if (worker.onmessage) {
                    worker.onmessage(event);
                }
            }, 0);
        },
        // ... other methods
    };
    return worker;
};
```

**Result:** FAILED
- Error: `undefined is not an object (evaluating 't.importPublicKey')`
- Test logs: b9b447a
- **Issue:** Crypto library expects actual crypto results, not echoed input

---

### ❌ Approach 5: Delete Worker Entirely
**Strategy:** Delete `window.Worker` to trigger Proton's built-in fallback mode.

**Implementation:**
```javascript
delete window.Worker;
delete window.SharedWorker;
```

**Result:** FAILED
- Error: `Can't find variable: Worker`
- Test logs: b7a9bbe
- **Issue:** Proton code accesses `Worker` directly without checking existence first

---

### ❌ Approach 6: Set Worker to undefined
**Strategy:** Set `window.Worker = undefined` so Proton can detect it's not available.

**Implementation:**
```javascript
window.Worker = undefined;
window.SharedWorker = undefined;
```

**Result:** FAILED
- Error: `undefined is not a constructor (evaluating 'new Worker(...)')`
- Test logs: b2be786
- **Issue:** Proton code calls `new Worker()` before checking if Worker exists

---

## Common Patterns Observed

### Login Flow Always Succeeds Partially
All approaches show the same successful API calls:
```
POST /api/auth/v4/sessions -> 200 (AccessToken received)
POST /api/core/v4/auth/cookies -> 200 (Cookies set)
POST /api/core/v4/auth/info -> 200
```

But then gets stuck in challenge retry loop:
```
[Navigation] tauri://localhost/api/challenge/v4/html?Type=0&Name=login&Retry=1
[Navigation] tauri://localhost/api/challenge/v4/html?Type=0&Name=login&Retry=2
```

Never reaches:
```
GET /assets/version.json  <- Drive app initialization
```

### Worker Error Location
Worker is created at: `tauri://localhost/account/assets/static/public-index.2ae8d2f5.js:1003:87490`

This is likely webpack-bundled code that doesn't check for Worker support before creating it.

---

## ✅ SOLUTION: Source Code Patching

### Chosen Approach: Option 1 (Patch WebClients Source)
We're building WebClients from **source code** specifically to avoid minified bundles. We can patch before building!

### Implementation
Use **patch files** applied during build process (standard packaging approach):

**Structure:**
```
protondrive-linux/
├── patches/
│   └── webclients/
│       └── 001-tauri-worker-compat.patch
├── scripts/
│   └── build-webclients.sh  (applies patches before building)
└── .github/workflows/
    └── *.yml  (apply patches in CI/CD)
```

**Patch Content:**
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

### Why This Works
1. **Proton has built-in fallback** - When `hasModulesSupport()` returns false, they load `@proton/crypto/lib/worker/api` directly in main thread
2. **Clean detection** - `window.__TAURI__` exists in all our Tauri builds
3. **No regression** - AppImage/AUR will still use Workers (they work there)
4. **Standard practice** - Patch files are how distro packages modify upstream source

### Build Process
```bash
# 1. Clone WebClients
git clone https://github.com/ProtonMail/WebClients.git

# 2. Apply patches
cd WebClients
git apply ../patches/webclients/001-tauri-worker-compat.patch

# 3. Build as normal
yarn install
yarn workspace proton-drive build:web

# 4. Patch is now in the webpack bundle
# hasModulesSupport() returns false in Tauri → non-Worker mode activated
```

### See Full Details
**Complete implementation plan:** `IMPLEMENTATION_PLAN.md`

---

---

## Session 2025-12-29: Patch Timing Issues

### ❌ Approach 7: window.__TAURI__ Check in hasModulesSupport()

**Status:** FAILED

**Patch Applied:**
```typescript
export const hasModulesSupport = () => {
    if (typeof window !== 'undefined' && (window as any).__TAURI__) {
        return false;
    }
    const script = document.createElement('script');
    return 'noModule' in script;
};
```

**Result:** Worker error still occurs
- Error: `undefined is not a constructor (evaluating 'new Worker(new URL(r.p+r.u(1711),r.b))')`
- Patch WAS included in build (confirmed `__TAURI__` in bundle)
- Bundle hash changed: `2ae8d2f5` → `06cf0bee` (confirming rebuild)

**Root Cause Analysis:**
`window.__TAURI__` is NOT available during early module initialization!

Tauri's injection sequence:
1. WebKitGTK loads HTML
2. Script tags begin executing (crypto init happens here)
3. Tauri IPC bridge initializes
4. `window.__TAURI__` is set (TOO LATE!)

**Key Insight:** The crypto worker initialization happens BEFORE Tauri sets `window.__TAURI__`.

---

### ✅ Approach 8: URL Protocol Check + PublicPath Fix

**Status:** WORKING - Login and 2FA passed!

**Rationale:** `window.location.protocol` is set IMMEDIATELY when the page loads, before ANY JavaScript executes.

**Patch:**
```typescript
export const hasModulesSupport = () => {
    // Check URL protocol (available immediately) or __TAURI__ global (set after init)
    if (typeof window !== 'undefined' && (window.location?.protocol === 'tauri:' || (window as any).__TAURI__)) {
        return false;
    }
    const script = document.createElement('script');
    return 'noModule' in script;
};
```

**Why This Should Work:**
- `window.location.protocol` = `'tauri:'` for all Tauri apps
- Available from first line of JavaScript execution
- No dependency on Tauri IPC initialization

**Additional Fix Required: PublicPath in runtime.js**

The webpack runtime has `k.p="/"` and chunk paths like `/account/assets/...`.
Combined: `"/" + "/account/..." = "//account/..."` which is a protocol-relative URL!

With `tauri://localhost` base, `//account/...` becomes `tauri://account/...` (WRONG!)

**Fix:** Change `k.p="/"` to `k.p=""` in runtime.js:
```bash
sed -i 's/k\.p="\/"/k.p=""/g' runtime.*.js
```

This fix must be applied to BOTH:
1. Account app: `applications/drive/dist/account/assets/static/runtime.*.js`
2. Drive app: `applications/drive/dist/assets/static/runtime.*.js`

---

## Test Environment
- **OS:** Fedora 43 (Linux 6.17.1)
- **System WebKitGTK:** webkit2gtk4.1
- **Tauri:** 2.0
- **DISTRO_TYPE:** Set at compile-time via environment variable

## Related Files
- `IMPLEMENTATION_PLAN.md` - Complete solution documentation
- `FEDORA_BUILD_STATUS.md` - Current build status and roadmap
- `src-tauri/src/main.rs` - DISTRO_TYPE-based init scripts
- `patches/webclients/001-tauri-worker-compat.patch` - The fix (to be created)
- `scripts/build-webclients.sh` - Applies patches before building
- `WebClients/packages/shared/lib/helpers/setupCryptoWorker.ts` - Proton's fallback logic
- `WebClients/packages/shared/lib/helpers/browser.ts` - Target file for patch
