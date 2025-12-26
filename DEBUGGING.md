# Proton Drive Linux - Debugging Log

## Current Approach
Simple Tauri wrapper around Proton WebClients. The WebClients JavaScript handles ALL authentication, cookies, and session management. Rust provides HTTP proxy for API calls (to bypass CORS).

## Zero Trust Architecture Notes
- Proton uses Zero Knowledge encryption - API returns encrypted PGP blobs
- File names, metadata are Base64-encoded PGP ciphertexts
- WebClients JS decrypts locally using user's Address Key
- Rust proxy never sees plaintext - just passes encrypted data through
- This is why "dumb proxy" approach works perfectly

## Key Drive API Endpoints (for reference)
- `GET /api/drive/v1/volumes` - List storage volumes
- `GET /api/drive/v1/shares` - List shares (root + shared folders)
- `GET /api/drive/v1/shares/{ID}/links` - Directory listing (encrypted)
- `GET /api/drive/v1/events/{EventID}` - Sync/polling for changes

## Current Architecture

```
┌─────────────────────────────────────────┐
│  WebClients JS (handles everything)     │
│  - Auth, cookies, tokens                │
│  - Encryption/decryption                │
│  - All Drive logic                      │
└─────────────────┬───────────────────────┘
                  │ fetch('/api/...')
                  ▼
┌─────────────────────────────────────────┐
│  JS Fetch Interceptor (init_script)     │
│  - Intercepts /api/ calls               │
│  - Forwards to Tauri IPC                │
└─────────────────┬───────────────────────┘
                  │ invoke('proxy_request')
                
                  ▼
┌─────────────────────────────────────────┐
│  Rust proxy_request                     │
│  - Shared reqwest Client                │
│  - Cookie jar enabled (cookie_store)   │
│  - Forwards headers as-is               │
│  - Returns response as-is               │
└─────────────────┬───────────────────────┘
                  │ reqwest (with cookie jar)
                  ▼
┌─────────────────────────────────────────┐
│  https://mail.proton.me/api/*           │
└─────────────────────────────────────────┘
```

## Iterations Tried

### 1. Native SRP Auth (Removed)
- Tried implementing Proton SRP auth in Rust using `proton-srp` crate
- Added `auth.rs` module with AuthManager
- **Problem**: Overengineered - WebClients already handles auth
- **Result**: Removed, not needed

### 2. Cookie Management via JS (Failed)
- Tried forwarding `document.cookie` as header
- Tried setting `document.cookie` from Set-Cookie responses
- **Problem**: `Session-Id` has `HttpOnly` flag - JS cannot access it
- **Result**: Approach fundamentally broken

### 3. Cookie Management via Rust Cookie Jar (Current)
- Use `reqwest` with `cookie_store(true)` feature
- Shared `Client` instance across all requests
- Cookies automatically stored and forwarded
- **Status**: Testing

## Key Finding: HttpOnly Cookies

**The `Session-Id` cookie has `HttpOnly` flag - JavaScript cannot access it.**

Actual cookie from API:
```
Session-Id=xxx; Domain=proton.me; Path=/; HttpOnly; SameSite=None; Secure; Max-Age=7776000
Tag=default; Path=/; SameSite=None; Secure; Max-Age=7776000
```

- `HttpOnly` means JavaScript's `document.cookie` CANNOT read or write this cookie
- This breaks any JS-based cookie forwarding approach
- Solution: Use reqwest's built-in cookie jar to handle cookies in Rust

## Current Status

### What Works
- App launches, frontend loads
- Stats endpoint: `POST /api/data/v1/stats` → 200
- Cookies received and stored by reqwest cookie jar
- JS console logging to Rust terminal working

### What Doesn't Work (Investigating)
- After stats call, NO other API calls are made
- Frontend shows login page but doesn't attempt auth calls
- No JS errors visible in console

### Observed Behavior (30 second test)
```
[JS] [LOG] [Tauri] Fetch + XHR proxy installed
[JS] [FETCH] GET /assets/static/sprite-icons.xxx.svg  (native fetch, not proxied)
[JS] [FETCH] GET /assets/static/file-icons.xxx.svg   (native fetch, not proxied)
[JS] [FETCH] post tauri://localhost/api/data/v1/stats
[Proxy] POST https://mail.proton.me/api/data/v1/stats
[Proxy] 200 <- https://mail.proton.me/api/data/v1/stats
... (no more API calls)
```

## Possible Issues Being Investigated

1. **Login requires user interaction** - Frontend showing login form, waiting for input
2. **SSO redirect** - Login may redirect to `account.proton.me` (different domain)
3. **Silent frontend error** - Something broken but not throwing visible error
4. **CORS on assets** - Static assets (CSS/JS) might be failing silently

## Key Files

- `src-tauri/src/main.rs` - Rust proxy with cookie jar
- `src-tauri/Cargo.toml` - Dependencies (reqwest with cookies feature)
- `WebClients/applications/drive/dist/` - Built frontend

## Environment
- Tauri 2.0.9
- reqwest 0.12 with `cookies` feature
- Manjaro Linux
- WebKitGTK

## Debug Features Added
- JS console.log/error/warn → Rust terminal (`[JS] [LOG/ERR/WARN]`)
- All fetch calls logged (`[JS] [FETCH]`)
- Proxy requests logged (`[Proxy] METHOD URL`)
- Unhandled errors caught

## API Base URL
```
https://mail.proton.me
```
NOT `api.proton.me` or `drive.proton.me`

## Latest Findings (Session 2)

### Visual State
- App shows Proton logo with animated loading message
- Not progressing past loading screen
- Page appears to reload (script installs multiple times)

### Observed Behavior
```
[JS] [LOG] [Tauri] Fetch + XHR proxy installed  (appears twice = page reload)
[JS] [FETCH] GET /assets/static/sprite-icons.xxx.svg  (200 OK)
[JS] [FETCH] GET /assets/static/file-icons.xxx.svg   (200 OK)
[JS] [WARN] IPC custom protocol failed, Tauri will now use the postMessage interface instead
[JS] [WARN] Couldn't find callback id xxx (callbacks lost on reload)
[JS] [FETCH] post tauri://localhost/api/data/v1/stats
[Proxy] POST https://mail.proton.me/api/data/v1/stats
[Proxy] 200 <- https://mail.proton.me/api/data/v1/stats
[Proxy] Body: {"Code":1000}
```

### Key Issues
1. **Page reloading** - Init script runs multiple times
2. **IPC protocol warning** - Falls back to postMessage (not fatal)
3. **Lost callbacks** - Callbacks from before reload are orphaned
4. **Only stats call** - No auth/core/drive API calls being made

### Reload Code Found
`packages/components/containers/app/errorRefresh.ts`:
- Reloads on chunk loading errors
- Reloads on API errors (once)
- Uses sessionStorage to track reload attempts

### No Visible Errors
- No UNCAUGHT errors
- No storage/IndexedDB errors
- No chunk loading errors visible
- Stats endpoint succeeds

### Hypothesis
The app may be:
1. Stuck waiting for something we can't see
2. Hitting an error that's caught but causes reload
3. Missing a required initialization call

## ROOT CAUSE FOUND

### The SSO Redirect Loop

When no session exists:
1. `bootstrap.loadSession()` throws `InvalidSessionError`
2. `handleInvalidSession()` is called
3. `requestFork()` calls `replaceUrl()`
4. `replaceUrl()` does `document.location.replace('https://account.proton.me/authorize?...')`
5. Tauri WebView tries to navigate to external URL
6. Navigation fails or triggers reload
7. App loads again → repeat

### Code Path
```
loadSession() → InvalidSessionError
→ handleInvalidSession() [logout.ts]
→ handleLogout() [logout.ts]
→ requestFork() [fork/consume.ts]
→ replaceUrl(getAppHref(SSO_PATHS.AUTHORIZE, APPS.PROTONACCOUNT))
→ document.location.replace('https://account.proton.me/authorize?...')
```

### Why This Happens
- Proton apps use SSO (Single Sign-On) via account.proton.me
- No valid session = redirect to account.proton.me for login
- Tauri WebView can't properly navigate to external domains
- Results in infinite reload loop

## Possible Solutions

### 1. Override replaceUrl (Quick Fix)
Intercept `document.location.replace()` to detect SSO redirects:
- Open account.proton.me in system browser
- Handle OAuth callback back into app

### 2. Embed Login Form
- Intercept the SSO redirect
- Show account.proton.me in an iframe or new window within Tauri
- Capture the auth tokens from the callback

### 3. Native Auth Flow
- Implement Proton SRP auth in Rust (we tried this before)
- Skip SSO entirely by authenticating directly against API

### 4. Session Injection (for testing)
- Log into drive.proton.me in browser
- Extract session cookies/tokens
- Inject into Tauri app to skip SSO

## Session 3 - Navigation Intercept Fix

### Problem with JS-level intercept
The JavaScript `document.location.replace` intercept didn't work because:
- WebClients JavaScript captures `document.location.replace` at module load time
- Our init script runs after the JS bundle has already loaded
- The captured reference points to the original function, not our override

### Solution: Rust-level navigation intercept
Used Tauri's `on_navigation` callback to intercept at the WebView level:

```rust
.on_navigation(move |url| {
    if url.host_str() == Some("account.proton.me") {
        println!("[SSO] Intercepted redirect to account.proton.me");
        // Open in system browser
        let _ = tauri_plugin_shell::ShellExt::shell(&app_handle)
            .open(url.as_str(), None);
        return false; // Cancel navigation in webview
    }
    // Allow tauri:// and localhost URLs
    url.scheme() == "tauri" || url.host_str() == Some("localhost") ...
})
```

### Current Status: LOGIN PAGE WORKING

The app now shows a login page instead of getting stuck in a reload loop:

```
[Navigation] Attempting to navigate to: tauri://localhost
[Navigation] Attempting to navigate to: tauri://localhost/login?reason=session-expired&type=self#sessions=W10
[Proxy] POST https://mail.proton.me/api/data/v1/stats
[Proxy] 200 <- https://mail.proton.me/api/data/v1/stats
[Proxy] Body: {"Code":1000}
```

### What's Working Now
1. App launches and loads frontend
2. Navigation intercept catches external URLs
3. Stats API endpoint works (200 OK, `{"Code":1000}`)
4. Login page is displayed to user
5. No more infinite reload loop

### Next Steps
1. Test login form - enter credentials and verify auth API calls work
2. If SSO redirect happens during login, system browser will open
3. May need to handle OAuth callback from system browser back to app

### Technical Details
- `#sessions=W10` = Base64 for `[]` (empty sessions array)
- `reason=session-expired` indicates no valid session found
- `type=self` means user needs to authenticate themselves

## Session 4 - Login Form & Navigation Blocking

### Problem: Login Redirect Loop
Even with JS intercept, the app was stuck in a redirect loop:
1. App loads → no session → redirect to `/login`
2. `/login` loads same app → no session → redirect to `/login`

### Root Cause
- JS `Location.prototype.replace` intercept wasn't catching the redirects
- The WebClients code triggered navigation before our init script could intercept

### Solution: Block `/login` at Tauri Level
Modified `on_navigation` callback to block `/login` navigations:

```rust
.on_navigation(move |url| {
    // Block /login navigations - show login form instead
    if url_str.contains("/login") {
        println!("[AUTH] Blocked /login navigation");
        return false;  // Block navigation
    }
    // Allow other tauri:// URLs
    url.scheme() == "tauri" || ...
})
```

### Custom Login Form
Added a login form overlay that appears after 5 seconds of detecting a stuck state:
- Detects when app has loader but no session
- Shows a styled login form
- Calls Proton auth API via our proxy

### Current Status: LOGIN FORM WORKING

```
[Navigation] Attempting to navigate to: tauri://localhost/login?...
[AUTH] Blocked /login navigation - will show login form via JS
[JS] [LOG] [INIT] Login check #5 hasContent=true hasLoader=true
[JS] [LOG] [INIT] App appears stuck, showing login form
```

### What's Working Now
1. App launches and loads frontend
2. `/login` navigation blocked at Rust level
3. Custom login form appears after 5 seconds
4. No more infinite redirect loop
5. Stats API works (200 OK)
6. Login form can make auth API calls

### What Needs Work
1. **SRP Authentication** - The login form can call `/api/auth/v4/info` but needs full SRP implementation
2. **Session Storage** - After successful auth, need to store session where WebClients expects it

### SRP Options
1. **proton-crypto-rs** - Official Proton Rust crypto (from GitHub, not crates.io)
2. **Proton-API-Bridge** - Go library that already works (user has it)
3. **JavaScript SRP** - Use the bundled `@proton/srp` after bundle loads

### Key Files Modified
- `src-tauri/src/main.rs` - Navigation blocking + login form injection

## Session 5 - Account App Integration (SUCCESS)

### Solution
Instead of custom login forms or native SRP, use Proton's official `account` app (part of WebClients) for SSO authentication.

### Steps Taken
1. Built the account app: `yarn workspace proton-account build:web`
2. Copied account dist to drive dist: `cp -r .../account/dist/* .../drive/dist/account/`
3. Modified account's `index.html`:
   - Changed `<base href="/">` to `<base href="/account/">`
   - Changed all `src="/assets/...` to `src="/account/assets/...`
   - Changed all `href="/assets/...` to `href="/account/assets/...`
4. Copied account's chunk files to root assets for worker compatibility
5. Updated `on_navigation` to rewrite `/login` paths to `/account/`

### Navigation Rewriting
```rust
.on_navigation(move |url| {
    // Rewrite /login paths to /account/ (local SSO)
    if url.path().starts_with("/login") {
        let local_url = format!("tauri://localhost/account/{}{}", query, fragment);
        // Navigate to account app
        window.navigate(url_clone.parse().unwrap());
        return false; // Block original navigation
    }

    // Also handle account.proton.me and drive.proton.me...
})
```

### Proxy Fix
Fixed serialization error by ensuring all header values are strings:
```js
const cleanHeaders = {};
for (const [k, v] of Object.entries(headers)) {
    cleanHeaders[k] = String(v);
}
```

### Current Status: ACCOUNT APP WORKING

```
[Navigation] tauri://localhost/login?...
[SSO] Rewriting /login to account app: tauri://localhost/account/?...
[Proxy] POST https://mail.proton.me/api/auth/v4/sessions
[Proxy] 200 <- {"Code":1000,"AccessToken":"...","UID":"..."}
[Proxy] POST https://mail.proton.me/api/core/v4/auth/cookies
[Proxy] 200 <- {"Code":1000,"UID":"..."}
[Proxy] GET https://mail.proton.me/api/domains/available?Type=login
[Proxy] 200 <- {"Code":1000,"Domains":["proton.me","protonmail.com"]}
```

### What Works Now
1. App launches and loads drive frontend
2. Drive detects no session → redirects to `/login`
3. `/login` rewritten to `/account/` → account app loads
4. Account app creates anonymous session (200 OK)
5. Cookie storage works (200 OK)
6. Domain lookup works (200 OK)
7. Feature flags work (200 OK)
8. Login form is displayed to user

### Architecture
```
Drive App (/) ──► /login redirect ──► Account App (/account/)
                                            │
                                            ▼
                                      Login Form
                                            │
                                            ▼
                              SRP Auth via proxy_request
                                            │
                                            ▼
                        ◄── Redirect back to Drive (/)
```

### Next Steps
1. User enters credentials in account app login form
2. Account app handles SRP authentication (already bundled)
3. After successful login, account redirects to `drive.proton.me`
4. Our navigation handler rewrites that back to `/`
5. Drive app loads with valid session

## Session 6 - CAPTCHA Challenge (In Progress)

### Problem: Login Requires CAPTCHA
When attempting to login, API returns Code 9001 (HUMAN_VERIFICATION_REQUIRED):
```json
{
  "Code": 9001,
  "Error": "For security reasons, please complete CAPTCHA...",
  "Details": {
    "HumanVerificationToken": "xxx",
    "HumanVerificationMethods": ["captcha"],
    "WebUrl": "https://verify.proton.me/?methods=captcha&token=xxx"
  }
}
```

### CAPTCHA Flow in WebClients
1. `HumanVerificationModal` is lazy-loaded when 9001 is received
2. Modal contains `Captcha.tsx` component
3. Captcha component creates an iframe to `/api/core/v4/captcha?Token=xxx`
4. The iframe loads hCaptcha widget from hcaptcha.com CDN
5. User completes captcha, token sent via postMessage
6. Token used to retry the auth request

### Approaches Tried

#### 1. Open verify.proton.me in Browser (Rejected by User)
- User explicitly said: "no... we will never accept captcha in browser"
- Must be in-app solution

#### 2. Build and Embed Verify App
- Built `yarn workspace proton-verify build:web`
- Copied to `drive/dist/verify/`
- Fixed paths in index.html
- **Problem**: Caused infinite redirect loop - verify app itself navigates to `/api/core/v4/captcha`

#### 3. Rewrite iframe URL to External API (Partial Success)
- Intercept iframe src, rewrite to `https://mail.proton.me/api/core/v4/captcha`
- Allow navigation to `mail.proton.me/captcha/` paths
- **Problem**: Cross-origin iframe - scripts don't execute properly

#### 4. Proxy CAPTCHA HTML via Tauri (Current Attempt)
- Added `fetch_captcha_html` Tauri command to fetch HTML from API
- Inject HTML into iframe using `srcdoc` or `document.write()`
- Add `<base href="https://mail.proton.me/">` for relative URLs
- **Problem**: hCaptcha widget not loading - shows "CAPTCHA verification is currently unavailable"

### Technical Findings

#### CAPTCHA HTML Structure
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <title>CAPTCHA</title>
</head>
<body>
<div id='html_element'></div>
<script nonce="xxx">
    // Inline jQuery
    // hCaptcha loading logic
    // Fallback: "CAPTCHA verification is currently unavailable"
</script>
</body>
</html>
```

#### Navigation Allowed
- `mail.proton.me/api/core/v4/captcha` - Captcha HTML
- `mail.proton.me/captcha/v1/assets/` - Captcha assets
- `hcaptcha.com` and `*.hcaptcha.com` - hCaptcha CDN

### Key Files for CAPTCHA
- `packages/components/containers/api/humanVerification/Captcha.tsx` - Creates iframe
- `packages/components/containers/api/humanVerification/HumanVerificationModal.tsx` - Modal wrapper
- `packages/components/containers/api/ApiModals.tsx` - Lazy loads modal on 9001
- `packages/shared/lib/api/helpers/withApiHandlers.ts` - Triggers verification flow

### Current Blockers
1. **Script Execution**: When injecting HTML via srcdoc/document.write, inline scripts may not execute properly
2. **hCaptcha CDN**: Even with navigation allowed, hCaptcha scripts may have CSP or sandbox issues
3. **Cross-Origin**: If iframe loads from different origin, postMessage communication may fail

### Possible Next Steps
1. **Debug hCaptcha loading**: Check if hCaptcha scripts are even being requested
2. **Try blob URL**: Create blob URL for captcha HTML instead of srcdoc
3. **Native hCaptcha**: Embed hCaptcha widget directly in parent window, not iframe
4. **WebView CSP**: Check if Tauri/WebKitGTK has Content Security Policy restrictions
