# Web Worker Debugging Log - RPM/deb Build Issues

## Current Status (v1.1.5)

**Both issues resolved:**

1. **Worker login:** Fixed by source patching `hasModulesSupport()` in WebClients's `browser.ts` to detect Tauri environment via `location.protocol` (not `window.__TAURI__`, which initializes too late). Patch: `patches/common/fix-tauri-worker-protocol.patch`.
2. **Chunk loading / SRI:** Fixed by adding `--no-sri` to `proton-pack build` commands in all three apps (drive, account, verify) via `scripts/fix_deps.py`, plus correcting nested app `publicPath` from `"/"` to `""`.

See the full debugging history below for details, failed approaches, and troubleshooting guidance.

---

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

## Approaches Attempted — Worker Login

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
- **Issue:** Worker loads but doesn't respond — possibly `importScripts()` issues or same tauri:// protocol restrictions inside Worker context

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

## ✅ SOLUTION: Source Code Patching (Worker)

### Chosen Approach: Option 1 (Patch WebClients Source)
We're building WebClients from **source code** specifically to avoid minified bundles. We can patch before building!

### Implementation
Use **patch files** applied during build process (standard packaging approach):

**Structure:**
```
protondrive-linux/
├── patches/
│   └── common/
│       └── fix-tauri-worker-protocol.patch
├── scripts/
│   └── build-webclients.sh  (applies patches before building)
└── .github/workflows/
    └── *.yml  (apply patches in CI/CD)
```

**Patch Content (v1.1.5 — uses `location.protocol` instead of `window.__TAURI__`):**
```diff
--- a/packages/shared/lib/helpers/browser.ts
+++ b/packages/shared/lib/helpers/browser.ts
@@ -7,6 +7,12 @@ const ua = uaParser.getResult();

 export const hasModulesSupport = () => {
+    // Detect Tauri environment via URL protocol (available immediately at JS startup)
+    // System WebKitGTK (RPM/deb/flatpak) doesn't support Workers from tauri:// protocol
+    // Force non-Worker crypto mode to use main-thread fallback
+    if (typeof window !== 'undefined' && (window.location?.protocol === 'tauri:' || (window as any).__TAURI__)) {
+        return false;
+    }
+
     const script = document.createElement('script');
     return 'noModule' in script;
 };
```

### Why This Works
1. **Proton has built-in fallback** — When `hasModulesSupport()` returns false, they load `@proton/crypto/lib/worker/api` directly in main thread
2. **Reliable detection** — `window.location.protocol` is set at page load, before any JavaScript runs. Unlike `window.__TAURI__` (too late)
3. **No regression** — AppImage/AUR will still use Workers (they work there)
4. **Standard practice** — Patch files are how distro packages modify upstream source

### Build Process
```bash
# 1. Clone WebClients
git clone https://github.com/ProtonMail/WebClients.git

# 2. Apply patches
cd WebClients
git apply ../patches/common/fix-tauri-worker-protocol.patch

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

**Status:** WORKING — Login and 2FA passed!

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

## Session 2026-05-07: Patch Staleness + Runtime Override Conflict

### ❌ CI Never Applied the Patch
- `build-linux-packages.yml` looked in `patches/webclients/` (doesn't exist)
- Actual patch location: `patches/common/`
- **All CI builds had zero patching applied** — root cause of persistent Worker failures in releases
- **Fix:** Corrected path in all three CI workflows (linux-packages, flatpak)

### ❌ Runtime `window.Worker = undefined` Conflicted with Patch
- `main.rs` set `window.Worker = undefined` for rpm/deb/flatpak/snap builds
- When patch IS applied, `setupCryptoWorker.ts` never uses Workers (uses main-thread path)
- But other Proton code could still call `new Worker()` — hitting `undefined` → crash
- This is exactly issue #32 "undefined is not a constructor"
- **Fix:** Removed runtime Worker override from `main.rs`; source patch handles everything

### ❌ Patch Hunk Line Number Stale
- WebClients added 2 import lines at top of `browser.ts`, shifting hunk from line 5→7
- **Fix:** Updated patch `@@ -5,6` → `@@ -7,6`; verified applies cleanly

### ✅ Current State (v1.1.5)
- Patch in `patches/common/fix-tauri-worker-protocol.patch` applies cleanly to current WebClients
- CI now correctly applies patch (`patches/common/`)
- `main.rs` no longer overrides Workers — relies entirely on patch
- Login + 2FA tested working on Fedora (RPM) in prior sessions

---

# Chunk Loading / SRI Debugging Log

## Problem Statement

After worker fix landed (v1.1.2), a new failure class emerged: the account app loads partially then shows **"Something went wrong, please refresh"**. Affects all package types (RPM, deb, Flatpak, AppImage) when loading locale chunks or date-fns after login.

**Symptoms (GitHub issues #34, #36):**
- "Error: Loading chunk 5269 failed after 3 retries. (/account/assets/static/locales/nl_NL.f4ab3a2c.chunk.js)"
- "Failure to load date-fns/en-CA.496dc653.chunk.js"
- Drive app: white screen (full blank page)
- Account app: "Something went wrong" modal after partial load

**Reported by:** brianandrewf (#36), pieter10-tech (#34)  
**Affects:** Linux Mint, Zorin OS, Debian-based, RPM-based

---

## Root Cause Analysis

### Cause 1: Webpack SRI (Subresource Integrity)

Proton's `proton-pack` build tool embeds SHA-384 hashes in `runtime.js` via `webpack-subresource-integrity`:

```js
// In runtime.js (built WITHOUT --no-sri):
k.sriHashes = {
  1711: "sha384-abc123...",
  5269: "sha384-def456...",
  // ... hundreds of chunk hashes
};
// Later, when loading a chunk:
i.integrity = k.sriHashes[e];  // UNCONDITIONAL assignment
```

**Problem:** When `sriHashes[e]` is `undefined` (chunk not in map), this sets `script.integrity = "undefined"` as a string. The browser's integrity check then REJECTS the script even though it loaded successfully.

**Secondary problem (static HTML):** `index.html` also has `integrity="sha384-..."` on static `<script defer>` tags. If `runtime.js` is modified post-build (to strip sriHashes), its content hash changes, and the browser rejects the file due to hash mismatch.

### Cause 2: Webpack PublicPath double-slash

Account app is served at `tauri://localhost/account/`. Runtime.js has `k.p="/"`.

When webpack loads a lazy chunk:
```js
url = k.p + k.u(chunkId)
// = "/" + "account/assets/static/locales/nl_NL.xxx.chunk.js"  
// = "/account/assets/static/locales/..."  ← looks right...
```

But the account/verify apps build with absolute paths: `"/assets/static/..."` not `"account/assets/..."`.

Combined with the nested deployment (account app is at `/account/`):
- Chunk path: `"/account/assets/static/locales/nl_NL.xxx.chunk.js"` (from build) 
- Public path: `"/"`
- Result: `"/" + "/account/assets/..."` = `"//account/assets/..."` (double-slash)
- On `tauri://localhost`: `//account/...` resolves as protocol-relative → `tauri://account/...` (WRONG HOST)

---

## Approaches Attempted — Chunk Loading / SRI

### ❌ Approach 1: Post-build sriHashes strip + HTML integrity removal

**Strategy:** After webpack build, sed/python3 to:
1. Strip `sriHashes` object: `.sriHashes={large_map}` → `.sriHashes={}`  
2. Strip unconditional integrity assignment: `i.integrity=k.sriHashes[e],` removed
3. Strip `integrity="..."` and `crossorigin="anonymous"` from `index.html`

**Implementation:**
```bash
# Strip sriHashes
find dist -name "runtime*.js" -exec python3 -c "
import re, sys
for p in sys.argv[1:]:
    c = open(p).read()
    c = re.sub(r'\.sriHashes=\{[^}]*\}', '.sriHashes={}', c)
    c = re.sub(r'[a-z]\.integrity=[a-z]\.sriHashes\[[a-z]\],', '', c)
    open(p,'w').write(c)
" {} \;

# Strip HTML integrity
sed -i 's| integrity="[^"]*"||g; s| crossorigin="anonymous"||g' index.html
```

**Result:** FAILED — White screen on drive app, "Something went wrong" on account app
- Root cause: The `sriHashes` regex `\{[^}]*\}` doesn't match multi-line objects or objects with nested braces
- The HTML `integrity=` strip alone isn't enough; the runtime JS still has partial SRI code
- We broke the build state by modifying files the browser was already tracking by hash

**Lesson:** Post-build sed patching of minified JS is fragile. The regex `\{[^}]*\}` cannot handle nested objects or multi-line source.

---

### ❌ Approach 2: Node.prototype.appendChild override (fetch-based chunk loader)

**Strategy:** Override `Node.prototype.appendChild` in initialization script to intercept `<script>` injection, fetch the chunk body, and eval it instead.

**Implementation:**
```javascript
const origAppendChild = Node.prototype.appendChild;
Node.prototype.appendChild = function(child) {
    if (child instanceof HTMLScriptElement && child.src) {
        const src = child.src;
        fetch(src).then(r => r.text()).then(code => eval(code));
        return child;
    }
    return origAppendChild.call(this, child);
};
```

**Result:** FAILED — Complete white screen, nothing loaded at all
- Root cause: `Node.prototype.appendChild` override affected ALL script injection, including WebKit's own HTML parser operations for static `<script defer>` elements in the HTML
- The parser calls appendChild when inserting static scripts during initial HTML parse — overriding this breaks the entire page load sequence
- **REVERTED** immediately

**Lesson:** DOM prototype overrides for `appendChild` are too broad. WebKit uses the same native code path for both static and dynamic script insertion.

---

### ✅ Approach 3: Build-time `--no-sri` flag (CORRECT FIX)

**Strategy:** Add `--no-sri` to the `proton-pack build` command in each app's `package.json` `build:web` script BEFORE running webpack. This disables SRI at the webpack plugin level — no hashes are generated, no `sriHashes` map is written, no `integrity=` attributes in HTML.

**Implementation (`scripts/fix_deps.py`):**
```python
# For drive app: add --no-sri to build:web script
if '--no-sri' not in new_script:
    new_script = new_script.rstrip() + ' --no-sri'

# Same for account and verify apps
```

**Resulting build commands:**
```
drive:   proton-pack build --appMode=standalone ... --no-sri
account: proton-pack build --appMode=sso --no-sri
verify:  proton-pack build --appMode=standalone ... --no-sri
```

**Combined with publicPath fix (in `scripts/build-webclients.sh`):**
```bash
# Change webpack publicPath from "/" to "" in nested apps' runtime.js
# So chunk URLs resolve relative to document base, not absolute
find applications/drive/dist/account -name "runtime*.js" -exec sed -i \
    's/\.p="\/"/.p=""/g' {} \;
```

**Why this works:**
1. `--no-sri` tells webpack NOT to embed SRI hashes → no `sriHashes` map, no `integrity=` in HTML
2. `publicPath=""` means chunk URLs are relative → correctly resolve to `tauri://localhost/account/assets/...`
3. No post-build modification of runtime.js needed → no HTML hash mismatch

**Status:** Fixed in v1.1.5 (2026-05-07). Clean rebuild removed SRI, corrected nested chunk paths, and validated Account/Drive loading.

---

## All Fork Analysis (2026-05-07)

Checked all 21 forks via GitHub API. Summary:

| Fork | Activity | Relevance |
|------|----------|-----------|
| Zamanhuseyinli, josselinonduty, ovestokke, MatthewChastain, vizyviz, janul, thomasarmel, nmarek1269, Mimir-Vor, llaith-oss, fzr76 | Only deleted CHANGELOG/TASKS docs | No code changes |
| sadsfae | CI trigger fixes | Same codebase level as main |
| EdoSag | Pivoted to Go/Fyne stack | Irrelevant |
| JC-Od, ColinMario, raddessi | rclone-based Python GUI | Completely different architecture |
| LayersOfAbstraction | AUR packaging only | No chunk loading fixes |
| Interested-Deving-1896 | Warp HTTP proxy + asset:// protocol | Different arch, no chunk-loading fix |

**Conclusion:** No fork has a specific SRI/chunk-loading fix. Our `--no-sri` build-time approach is the correct solution.

---

## Integrated Debugging Logs

### Session: 2026-05-07 v1.1.5 Fedora Login Validation

**Findings:**
- `--no-sri` was confirmed in Drive, Account, and Verify build commands.
- Rebuilt WebClients output had no `integrity=` attributes and no `sriHashes` runtime maps.
- Drive root runtime kept `publicPath="/"`; nested Account/Verify runtimes use relative `publicPath=""`.
- The previous white screen was partly caused by testing an older Rust binary with stale embedded frontend assets.
- The Account login refresh loop was caused by `/api/challenge/v4/html` iframe/document navigations being served as the Account SPA route.
- The CAPTCHA freeze was caused by treating captcha-internal `about:blank` navigation as completion before a verification token existed.

**Fixes Applied:**
- Build WebClients with `--no-sri` instead of post-build SRI stripping.
- Block all `/api/` document navigations; API traffic continues through the fetch/XHR proxy.
- Allow captcha-internal `about:blank` navigations while on the verification page.
- Treat CAPTCHA completion only as explicit return to `tauri://localhost/account/?hv_token=...&hv_type=...`.
- Store the token in Rust memory and add Proton human-verification headers to the retried auth request.
- Avoid forwarding console logs from external captcha pages to Rust to prevent Tauri ACL noise.

**Validated Result:**
- Fedora local release binary launched successfully.
- Login screen stayed stable with no refresh loop.
- CAPTCHA completed and returned a verification token.
- Auth retry consumed the token, reached 2FA, loaded app selection, and Drive opened.

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Check / Fix |
|---------|-------------|-------------|
| Infinite spinner during login | Worker not supported in WebKitGTK — patch not applied or wrong detection method | Verify `hasModulesSupport()` returns `false` in Tauri builds. Check: `grep "tauri:" dist/account/assets/static/runtime.*.js` |
| White screen (full blank page, no UI) | SRI hash mismatch, publicPath broken, or runtime.js completely missing — app can't boot | Check devtools console for SRI errors. Verify `--no-sri` is in build commands. Check `integrity=` attributes on `<script>` tags |
| "Something went wrong, please refresh" | Chunk loading failure after initial boot — locale, date-fns, or crypto chunks failing | Check Runtime publicPath: `grep '\.p="' runtime.*.js`. Should be `""` for nested account/verify apps, `"/"` for drive root |
| "undefined is not a constructor (evaluating 'new Worker(...)')" | Runtime `window.Worker = undefined` still in `main.rs` | Check `src-tauri/src/main.rs` for `window.Worker = undefined`. Should be removed in v1.1.5+ |
| CAPTCHA page loading inside app frame instead of separate dialog | Challenge navigation not intercepted by Rust proxy handler | Verify captcha navigation rules block `/api/challenge/v4/` navigations but allow captcha-internal `about:blank` |
| Login succeeds but immediately loops back to login screen | Auth challenge retry without human verification token being captured | Check CAPTCHA completion flow — expects `?hv_token=...&hv_type=...` return URL to `tauri://localhost/account/` |
| Flatpak-specific chunk errors (works on RPM/deb) | Flatpak sandbox blocking cross-origin or file-relative fetches | Verify `--filesystem=host` or appropriate Flatpak permissions for WebKitGTK asset loading |
| "patch does not apply" during build | WebClients upstream updated; patch hunk line numbers are stale | Run `git apply --reject` to see exact failures. Update `@@ -N,6` line offsets in `.patch` file |
| Build succeeds but old behavior persists | Rust binary embeds stale frontend assets — `cargo build` captured old dist | Ensure full rebuild order: `scripts/build-webclients.sh && cargo build --release` |

---

## Additional Debug Scenarios

### Debug Scenario A: Verifying Patches Were Applied

**Goal:** Confirm the `fix-tauri-worker-protocol.patch` was actually applied during build — the most common regression source.

**Check Build Logs:**
```bash
# Each CI workflow logs patch output:
grep "Applying patch" build.log
# Expected: "Applying patch: patches/common/fix-tauri-worker-protocol.patch"
# If absent, or path says patches/webclients/ (old, wrong path), patch was NOT applied
```

**Check Built Artifacts:**
```bash
# Confirm patch content made it into the bundle
cd applications/drive/dist/

# Look for the protocol check in account runtime
grep "window.location" account/assets/static/runtime.*.js | head -3
# Should show: (window.location?.protocol==='tauri:'...)

# Look for the hasModulesSupport patch
grep "hasModulesSupport" account/assets/static/runtime.*.js | head -3
# Should show patched version with tauri: check
```

**Check Runtime Behavior (in Tauri devtools console):**
```javascript
// These are available on the very first tick of JS execution:
console.log(window.location.protocol);
// Should be 'tauri:' for all Tauri builds

// To verify hasModulesSupport is truly returning false:
// Look for absence of Worker instantiation errors on login
// If no "The operation is insecure" or "Loading chunk" errors → patch working
```

### Debug Scenario B: Diagnosing White Screen vs Infinite Spinner vs Partial Crash

**Rule of Thumb — three distinct failure modes with different root causes:**

| Symptom | Root Cause Class | First Thing to Check |
|---------|-----------------|---------------------|
| **White screen** (nothing renders at all) | SRI mismatch, publicPath broken, or runtime.js missing — app can't bootstrap | Element inspector: are `<script>` tags present with correct `src=`? Network tab: are chunks being requested at all? |
| **"Something went wrong"** with partial UI loading | Chunk loading failure during lazy import (locale, date-fns, moment) | Console for `Loading chunk N failed` errors. Check which chunk ID is failing. |
| **Infinite spinner** during login | Worker instantiation error — crypto never initializes | Console for `The operation is insecure`. Check patch was applied and detection method is correct (`location.protocol`, not `__TAURI__`). |

**Step-by-step diagnosis:**
1. Open Tauri devtools (Ctrl+Shift+I or right-click → Inspect)
2. **Console tab:** Capture all errors before dismissing them. Look for:
   - `Loading chunk N failed after M retries` → SRI or publicPath issue
   - `The operation is insecure` → Worker/patch issue
   - `undefined is not a constructor` → stale runtime Worker override
   - `SyntaxError: Unexpected token '<'` → chunk fetched wrong URL (HTML instead of JS)
3. **Network tab:** Filter by `.js` / `.chunk.js`. Verify all chunk URLs:
   - Resolve correctly (no `//` double-slash in URL)
   - Return HTTP 200 with JS content type
   - Are served from `tauri://localhost/account/assets/...` not `tauri://account/...`
4. **Elements tab:** Check `<script>` tags for `integrity=` attributes:
   - If present, SRI stripping failed → rebuild with `--no-sri`
   - Check the `src` attributes match actual file paths

### Debug Scenario C: Stale Rust Binary with Old Frontend Assets

**Symptom:** Rebuilt WebClients with fixes applied, but the Tauri app still shows old behavior.

**Root Cause:** The Rust binary (`protondrive`) embeds the frontend at compile time. Running `cargo build` captures whatever is in `applications/drive/dist/` at that exact moment. If you built WebClients in one terminal but `cargo build` in another with a different working directory, or forgot to rebuild WebClients, the binary will embed stale assets.

**Diagnostic:**
```bash
# Check which runtime is embedded in the binary
strings target/release/protondrive | grep "runtime" | head -5
# Compare with expected chunk names from the fresh dist/
ls applications/drive/dist/account/assets/static/runtime.*.js
# If hashes or filenames don't match, the binary is stale
```

**Fix — full clean rebuild:**
```bash
cd WebClients
scripts/build-webclients.sh    # Applies patches, builds, fixes publicPath
cd ..
cargo build --release          # Embeds the fresh dist from applications/drive/dist/
```

**Prevention:** The CI workflows handle this automatically (clean checkout, then build-webclients.sh, then cargo build in the same runner). Local dev must replicate this exact order.

### Debug Scenario D: CAPTCHA vs Chunk Loading — Cross-Distro Failures

**Symptom:** "Login works on Fedora (RPM) but fails on Linux Mint / Zorin OS (deb) or Flatpak."

**Possible root causes to investigate:**

1. **WebKitGTK version differences** — Different distros ship different WebKitGTK versions with different security policies:
   ```bash
   # Check version on the affected distro:
   rpm -q webkit2gtk4.1       # Fedora/RPM
   dpkg -l | grep webkit2gtk  # Debian/Ubuntu
   flatpak info org.gnome.Sdk//44  # Flatpak runtime version
   ```

2. **CAPTCHA rendering differences** — Some distros have different default browser configurations affecting CAPTCHA iframe rendering:
   - Check if CAPTCHA page loads fully vs. shows "not supported" message
   - Verify `about:blank` navigation rules are correctly allowing captcha-internal navigations

3. **Flatpak sandbox interference** — Chunk fetches or Worker initialization blocked by sandbox permissions:
   ```bash
   flatpak run --command=bash com.protondrive.linux
   echo "Check /etc/hosts, network access, WebKit permissions"
   ```

4. **Build consistency** — Identical WebClients source should produce identical chunks, but verify:
   ```bash
   sha256sum applications/drive/dist/account/assets/static/runtime.*.js
   # Compare against a known-good build
   ```

**Collect on the affected distro:**
```bash
# Diagnostic bundle
echo "=== WebKitGTK ==="
rpm -q webkit2gtk4.1 2>/dev/null || dpkg -l | grep webkit2gtk
echo "=== Tauri ==="
grep 'tauri' src-tauri/Cargo.toml
echo "=== Build Log (patch section) ==="
grep -A2 "Applying patch" build.log
echo "=== Console Errors ==="
# Capture from Tauri devtools
```

### Debug Scenario E: SRI Still Present After `--no-sri` Build

**Symptom:** `integrity=` attributes still appear in built HTML even though `--no-sri` was added to build commands.

**Possible causes:**
1. **`--no-sri` in wrong `package.json` script** — Verify each app's `build:web` script:
   ```bash
   grep "build:web" WebClients/applications/drive/package.json
   grep "build:web" WebClients/applications/account/package.json
   grep "build:web" WebClients/applications/verify/package.json
   # Each should contain '--no-sri'
   ```
2. **`--no-sri` not passed to all `proton-pack build` calls** — Proton-pack may have multiple invocation patterns in the build script. Check `fix_deps.py` actually hit all three apps.
3. **Cached webpack build** — Clean dist before rebuilding:
   ```bash
   rm -rf applications/drive/dist
   ```

**Verify post-build:**
```bash
# Quick check for integrity attributes
grep -r "integrity=" applications/drive/dist/ --include="*.html"
# Should return nothing

# Check runtime.js for sriHashes
grep "sriHashes" applications/drive/dist/account/assets/static/runtime.*.js
# Should return nothing
```

### Debug Scenario F: CI Pipeline Patch Path Drift

**Symptom:** Patch was verified working in local builds but CI releases still exhibit Worker errors.

**Likely Cause:** The CI workflow files reference a different patch path than where the patch actually lives. This already happened once (see "CI Never Applied the Patch" above) and can recur.

**Check all CI workflows:**
```bash
# Search for all patch path references across CI configs
grep -r "patches/" .github/workflows/ .gitlab-ci.yml 2>/dev/null

# Expected output should point to patches/common/ — any reference to
# patches/webclients/ is stale and must be corrected
```

**Prevention:** When moving or renaming a patch file, run:
```bash
grep -r "old/patch/path" .github/workflows/ .gitlab-ci.yml
```
to find and update all stale references before committing.

---

## Test Environment (current)

- **OS:** Fedora 40 (Linux 6.14.5-100.fc40.x86_64)
- **System WebKitGTK:** webkit2gtk4.1 (system-installed)
- **Tauri:** 2.0
- **RAM:** 15GB (expanded from 3.8GB after OOM during parallel webpack builds)
- **Disk:** 64GB partition (expanded from 15GB via growpart + xfs_growfs)

## Related Files

- `src-tauri/src/main.rs` — DISTRO_TYPE-based init scripts (Worker override removed in v1.1.5+)
- `patches/common/fix-tauri-worker-protocol.patch` — Worker compat patch (uses `location.protocol`)
- `scripts/build-webclients.sh` — Applies patches before building, fixes publicPath
- `scripts/fix_deps.py` — Adds `--no-sri` to build commands for all three apps
- `WebClients/packages/shared/lib/helpers/setupCryptoWorker.ts` — Proton's fallback logic
- `WebClients/packages/shared/lib/helpers/browser.ts` — Target file for patch
- `.github/workflows/build-linux-packages.yml` — CI workflow (must reference `patches/common/`)
- `.github/workflows/flatpak.yml` — Flatpak CI workflow
- `.gitlab-ci.yml` — GitLab CI pipeline

## Related Issues

- GitHub #32: "undefined is not a constructor" — Runtime Worker override conflict (fixed v1.1.5)
- GitHub #34: Chunk loading error after login (Zorin OS/Debian) — Fixed by `--no-sri`
- GitHub #36: date-fns chunk loading failure (Linux Mint, Flatpak/AppImage) — Fixed by `--no-sri`
- GitHub #37: Challenge navigation blocked (superseded by v1.1.5 top-level captcha flow)
- GitHub #39: Checksum mismatch for v1.1.2 deb (filename spacing issue in SHA256SUMS)
- GitHub #40: Login problem on Debian (likely chunk loading, awaiting confirmation)
