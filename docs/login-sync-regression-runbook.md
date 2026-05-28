# Login Sync / SRI Regression Runbook

Use this runbook to verify that login-sync and SRI (Subresource Integrity)
fixes are correctly applied in CI builds and local development. Run through
these checks before tagging a release or after any change to the WebClients
build pipeline, patch files, or CI workflows.

## Overview

Proton Drive Linux ships three web apps inside a Tauri wrapper:

- **Drive app** — main file storage UI
- **Account app** — login, 2FA, settings (nested under `/account/`)
- **Verify app** — CAPTCHA, auth challenges (nested under `/verify/`)

Two classes of regression affect login:

1. **Web Worker incompatibility** — System WebKitGTK (RPM/deb/flatpak/snap)
   doesn't support Workers from `tauri://` protocol. Fix: patch WebClients
   `hasModulesSupport()` to return `false` in Tauri environments.
2. **SRI (Subresource Integrity) + path mismatches** — webpack embeds SHA-384
   hashes at build time via `webpack-subresource-integrity`. If hashes remain
   or publicPath is wrong, lazy chunks (locales, date-fns) fail to load,
   producing white screen or "Something went wrong" on login.

---

## CI Guardrails

### 1. Patch Application

The WebClients compat patch **must** be applied before every build:

| Check | Expected |
|-------|----------|
| Patch file exists | `patches/common/fix-tauri-worker-protocol.patch` |
| Applied by `scripts/build-webclients.sh` | Searches `patches/common/*.patch`, git-applies each |
| Applied by `.gitlab-ci.yml` | All build jobs call `scripts/build-webclients.sh` |
| Applied by Flatpak build | `packaging/com.proton.drive.yml` calls `scripts/build-webclients.sh` |

**Per-distro patches:** In addition to the common patch, `.gitlab-ci.yml` also
applies distro-specific patches from `patches/<type>/` (e.g. `patches/apk/`,
`patches/appimage/`, `patches/deb/`, `patches/aur/`). These handle
distro-specific build env quirks. The common patch is always the baseline.

**Verify patch is active** in a built dist:

```bash
# Check hasModulesSupport() returns false in Tauri context (TypeScript source)
grep -rF "window.location?.protocol === 'tauri:'" WebClients/packages/shared/lib/helpers/browser.ts

# Confirm the patched function is in the webpack bundle (transpiled JS)
grep -F "=== 'tauri:'" applications/drive/dist/assets/static/main.*.js
```

**If missing**, the patch hunk may be stale (WebClients upstream added/removed
lines near the target). Update the hunk offset in the `.patch` file:

```bash
cd WebClients
git apply --check ../patches/common/fix-tauri-worker-protocol.patch
# If this fails, the hunk @@ line numbers are wrong
```

### 2. SRI Hash Stripping (Safety Net)

Webpack's `webpack-subresource-integrity` plugin embeds SHA-384 hashes in
`runtime.js` and `index.html`. These must be stripped because:

- Modifying runtime.js post-build (e.g., fixing publicPath) invalidates the hashes
- Unconditional `i.integrity = sriHashes[e]` sets `integrity="undefined"` for
  chunks not in the hash map, which WebKitGTK rejects as a failed integrity match

**Primary fix:** `scripts/fix_deps.py` adds `--no-sri` to the `build:web`
script in each app's `package.json` **before** webpack runs. This disables
SRI at the webpack plugin level — no hashes are generated.

**Safety net in `scripts/build-webclients.sh`:** Post-build stripping in case
`--no-sri` was missed (e.g., WebClients updated and fix_deps.py didn't run):

```bash
# 1. Remove integrity/crossorigin from all HTML files (drive root, account, verify)
find applications/drive/dist -name "*.html" -exec sed -i \
  -e 's| integrity="[^"]*"||g' \
  -e 's| crossorigin="anonymous"||g' {} \;

# 2. Strip sriHashes object and unconditional integrity assignment
#    from all runtime.js files (drive root, account, verify)
find applications/drive/dist -name "runtime*.js" -exec python3 -c "
import re, sys
for p in sys.argv[1:]:
    c = open(p).read()
    c = re.sub(r'\.sriHashes=\{[^}]*\}', '.sriHashes={}', c)
    c = re.sub(r'[a-z]\.integrity=[a-z]\.sriHashes\[[a-z]\],', '', c)
    open(p,'w').write(c)
" {} \;
```

**Verify SRI is stripped:**

```bash
# No sriHashes entries — use find for portability (avoids ** globstar dependency)
find applications/drive/dist -name 'runtime*.js' -exec grep -c 'sriHashes' {} +
# Should return lines with 'sriHashes={}' only, not hash maps

# No integrity attributes in HTML
grep 'integrity=' applications/drive/dist/index.html
# Should return nothing

# No crossorigin in HTML
grep 'crossorigin="anonymous"' applications/drive/dist/index.html
# Should return nothing
```

**Verify `--no-sri` was applied at build time:**

```bash
# Check each app's package.json for --no-sri in build:web
grep -r "no-sri" WebClients/applications/*/package.json
# Expected: drive, account, and verify all have --no-sri in their build:web script
```

If `--no-sri` is missing from any app, `scripts/fix_deps.py` needs to be
run again or its regex may be stale.

### 3. PublicPath Fix

Webpack's `__webpack_public_path__` defaults to `"/"`. For the nested account
app at `tauri://localhost/account/`, this creates double-slash paths:

```
"/" + "/account/assets/..." = "//account/assets/..." (protocol-relative!)
"//account/..." on tauri:// = "tauri://account/..."  (WRONG HOST)
```

**Fix applied in `scripts/build-webclients.sh`:**

```bash
# Account app
find applications/drive/dist/account -name "runtime*.js" -exec sed -i \
  's/\.p="\/"/.p=""/g' {} \;

# Verify app (same fix)
find applications/drive/dist/verify -name "runtime*.js" -exec sed -i \
  's/\.p="\/"/.p=""/g' {} \;
```

**Verify publicPath:**

```bash
grep '\.p=""' applications/drive/dist/account/runtime*.js
# Should match — publicPath set to empty string

grep '\.p=""' applications/drive/dist/verify/runtime*.js
# Should match
```

### 4. Account/Verify Nested Path Fix

Asset paths in account and verify apps must be rewritten for nested deployment:

| Original | Fixed |
|----------|-------|
| `<base href="/">` | `<base href="/account/">` or `<base href="/verify/">` |
| `src="/assets/..."` | `src="/account/assets/..."` or `src="/verify/assets/..."` |
| `href="/assets/..."` | `href="/account/assets/..."` or `href="/verify/assets/..."` |
| `content="/assets/..."` | `content="/account/assets/..."` or `content="/verify/assets/..."` |

The build script also strips `integrity` and `crossorigin` attributes from
HTML during path fixing (same WebKitGTK SRI rejection issue documented above).

**Verify path fixes:**

```bash
# Account app base href must be correct
grep '<base href="/account/">' applications/drive/dist/account/index.html

# No unfixed absolute paths in account app
grep 'src="/assets/' applications/drive/dist/account/index.html
# Should return nothing
grep 'href="/assets/' applications/drive/dist/account/index.html
# Should return nothing

# Verify app base href
grep '<base href="/verify/">' applications/drive/dist/verify/index.html

# No unfixed absolute paths in verify app
grep 'src="/assets/' applications/drive/dist/verify/index.html
# Should return nothing
```

---

## Local Regression Test

Run the full build pipeline locally before pushing to CI:

### Step 1: Clean build

```bash
# Remove cached dist to force a fresh build
rm -rf WebClients/.codex-cache
rm -rf WebClients/applications/drive/dist

# Run the CI build script (matches what CI does)
bash scripts/build-webclients.sh
```

### Step 2: Verify all guardrails

```bash
echo "=== PATCH CHECK ==="
grep -c "== 'tauri:'" applications/drive/dist/assets/static/main.*.js | head -1 && \
  echo "PASS: patch present in bundle" || \
  echo "FAIL: patch not in webpack bundle"

echo "=== SRI CHECK ==="
if grep -q 'integrity=' applications/drive/dist/index.html; then
  echo "FAIL: integrity attributes remain in index.html"
else
  echo "PASS: SRI stripped from index.html"
fi

echo "=== NO-SRI FLAG CHECK ==="
if grep -q 'no-sri' WebClients/applications/*/package.json; then
  echo "PASS: --no-sri present in build scripts"
else
  echo "FAIL: --no-sri missing from build scripts"
fi

echo "=== PUBLICPATH CHECK ==="
if grep -q '\.p=""' applications/drive/dist/account/runtime*.js; then
  echo "PASS: account app publicPath fixed"
else
  echo "FAIL: account app publicPath not fixed"
fi
if grep -q '\.p=""' applications/drive/dist/verify/runtime*.js; then
  echo "PASS: verify app publicPath fixed"
else
  echo "FAIL: verify app publicPath not fixed"
fi

echo "=== NESTED PATH CHECK ==="
if grep -q '<base href="/account/">' applications/drive/dist/account/index.html; then
  echo "PASS: account app base href correct"
else
  echo "FAIL: account app base href wrong"
fi

if grep -q 'src="/assets/' applications/drive/dist/account/index.html; then
  echo "FAIL: account app has unfixed asset paths"
else
  echo "PASS: account app asset paths correct"
fi

if grep -q '<base href="/verify/">' applications/drive/dist/verify/index.html; then
  echo "PASS: verify app base href correct"
else
  echo "FAIL: verify app base href wrong"
fi

if grep -q 'src="/assets/' applications/drive/dist/verify/index.html; then
  echo "FAIL: verify app has unfixed asset paths"
else
  echo "PASS: verify app asset paths correct"
fi
```

### Step 3: Build and run packaged app

```bash
# Build the Tauri binary (AppImage for quick test)
npx @tauri-apps/cli build --target appimage

# Run and attempt login + 2FA
./src-tauri/target/release/Proton\ Drive &
```

Verify login flow completes:

1. App launches to login page (not white screen)
2. Credentials accepted, no infinite spinner
3. 2FA challenge loads (if enabled)
4. Drive main UI loads after authentication
5. Lazy chunks (locales, date-fns) load without "Something went wrong"

---

## CI Pipeline Triggers

Builds that test login sync run on:

| Trigger | CI System | Pipeline |
|---------|-----------|----------|
| Push to `main` | Both | GitLab CI — all build jobs; GitHub Actions — `package-workflows.yml` |
| Push to `feature/**`, `fix/**`, `chore/**` | Both | GitLab CI — all build jobs; GitHub Actions — `package-workflows.yml` |
| PR to `main` | GitHub Actions | `package-workflows.yml` — build + upload |
| Push tag `v*` | Both | GitLab CI — release + publish stages; GitHub Actions — release build |
| `workflow_dispatch` | Both | Manual trigger |

### GitLab CI SRI-specific check

The CI build calls `scripts/build-webclients.sh` which in turn runs
`scripts/fix_deps.py` before the webpack build. `fix_deps.py` patches each
app's `package.json` to add `--no-sri` to the `build:web` command,
disabling SRI at the webpack plugin level.

Verify the `--no-sri` flag is present in all three apps' build scripts:

```bash
grep 'no-sri' WebClients/applications/*/package.json
# Expected: --no-sri appears in the build:web script for drive, account, and verify
```

### GitHub Actions patch path check

All GitHub Actions workflow implementations under `.github/workflows/` use
`scripts/build-webclients.sh` which handles patches from `patches/common/`.
Verify no workflow references a stale `patches/webclients/` path:

```bash
grep -r "patches/webclients" .github/workflows/
# Expected: no matches (historical bug — was `patches/webclients/`, fixed to `patches/common/`)
```

---

## Known Pitfalls

### Patch stale on WebClients update

When WebClients upstream adds/removes imports at the top of `browser.ts`, the
patch hunk `@@ -5,6` (or similar) drifts. Symptoms: CI build succeeds but
patch silently fails — `git apply` returns non-zero, but the build script
skips already-applied detection and only flags conflicts. **Always check**
the patch applied by verifying the content in the bundle (step 2 above).

### `window.__TAURI__` timing

Do NOT rely on `window.__TAURI__` to detect Tauri. It's set AFTER early
module initialization — the crypto worker starts before the Tauri IPC bridge
is ready. Use `window.location.protocol === 'tauri:'` instead (available
from the first line of JS execution).

### Runtime Worker override in main.rs

The old approach overrode `window.Worker = undefined` in `main.rs`. This
**conflicts** with the source patch: when the patch IS applied,
`setupCryptoWorker.ts` never uses Workers, but other Proton code may still
call `new Worker()` — hitting `undefined` causes a crash. **Do NOT add**
Worker overrides in `main.rs`. The source patch in `patches/common/` is the
correct and only fix path.

### SRI regex fragility

The SRI stripping regex `\.sriHashes=\{...\}` uses `[^}]` which fails on
multi-line or nested hash maps. The build script's Python approach handles
this correctly, but if you're manually editing runtime.js, beware. The
primary fix is `--no-sri` at build time (via `fix_deps.py`); the post-build
Python stripping is a safety net only.

### Account and Verify build failures are non-fatal

In `scripts/build-webclients.sh`, both account and verify builds exit with a
warning, NOT a hard error:

```bash
wait $ACCOUNT_PID && echo "✅ Account build complete" || echo "⚠️  Account build failed (login may not work)"
wait $VERIFY_PID  && echo "✅ Verify build complete"  || echo "⚠️  Verify build failed (captcha optional)"
```

A failed account build means **login will not work** — the account app
`index.html` won't be deployed under `/account/`. A failed verify build
means CAPTCHA/auth challenges may not display. Always verify both account
and verify dist directories were produced after the build finishes.

### Per-distro patches can overlap with common patches

GitLab CI jobs apply a distro-specific patch (e.g. `patches/apk/alpine.3.20.patch`)
before calling `build-webclients.sh`. If a distro patch and the common patch
touch the same file, conflicts may arise. Verify by checking the build log for
"Failed to apply" errors. The common patch in `patches/common/` should always
be the authoritative source for the `hasModulesSupport()` fix.

---

## Quick Reference

```bash
# Verify patch in bundle (transpiled JS)
grep "=== 'tauri:'" applications/drive/dist/assets/static/main.*.js | head -3

# Verify --no-sri was applied at build time
grep "no-sri" WebClients/applications/*/package.json

# Verify SRI stripping (all apps)
find applications/drive/dist -name 'runtime*.js' -exec sh -c '
  for f; do
    if grep -q "\.sriHashes" "$f" && ! grep -q "\.sriHashes={}" "$f"; then
      echo "SRI NOT stripped: $f"
    fi
  done
' sh {} +

# Verify publicPath (account + verify)
grep '\.p=""' applications/drive/dist/account/runtime*.js
grep '\.p=""' applications/drive/dist/verify/runtime*.js

# Verify nested paths
grep 'base href="/account/"' applications/drive/dist/account/index.html
grep 'base href="/verify/"' applications/drive/dist/verify/index.html

# Check for unfixed paths
grep -r 'src="/assets/' applications/drive/dist/account/
grep -r 'src="/assets/' applications/drive/dist/verify/

# Full smoke test
rm -rf WebClients/.codex-cache WebClients/applications/drive/dist
bash scripts/build-webclients.sh && \
  npx @tauri-apps/cli build --target appimage && \
  echo "Ready for login testing"
```
