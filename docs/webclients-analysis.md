# WebClients Analysis

This document analyzes Proton's upstream `ProtonMail/WebClients` repository as a reference source. The Go `dev` branch does not currently embed or build WebClients.

## Why Analyze WebClients

WebClients is useful because it shows how Proton's own web Drive app handles:

- Drive bootstrap and session loading.
- Account/login app flow.
- human verification.
- browser-side download strategy.
- crypto worker fallback.
- Proton monorepo build requirements.

That knowledge can inform the Go client, but it is not current runtime behavior in this branch.

## Upstream Checkout

Clone locally when needed:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Observed upstream metadata at analysis time:

| Item | Value |
| --- | --- |
| Root package manager | `yarn@4.13.0` |
| Node engine | `>= 22.14.0 <23.6.0` |
| Drive app | `applications/drive`, package `proton-drive` |
| Drive version | `5.2.0` |
| Account app | `applications/account`, package `proton-account` |
| Verify app | `applications/verify`, package `proton-verify` |

## Drive App Bootstrap

Important files:

```text
WebClients/applications/drive/src/app/index.tsx
WebClients/applications/drive/src/app/App.tsx
WebClients/applications/drive/src/app/bootstrap.ts
WebClients/applications/drive/src/app/config.ts
```

Bootstrap flow in `bootstrap.ts`:

1. Create API client from Proton config.
2. Create authentication helper.
3. Initialize account bootstrap with config, auth, and locales.
4. Set up cross-storage.
5. Load session from path/search state.
6. Create history.
7. Create Unleash client.
8. Initialize Drive metrics.
9. Load persisted encrypted state.
10. Build Redux store.
11. Load user, user settings, features, locales, telemetry, and crypto.
12. Fetch Drive user settings.
13. Run account post-load.
14. Start event manager.
15. Register OPFS cleanup on logout.

The Go client will not reuse this directly, but the sequence is a useful map of the Proton web app's dependency order.

## Drive Download Strategy

Important files:

```text
WebClients/applications/drive/src/app/managers/fileSaver/fileSaver.ts
WebClients/applications/drive/src/app/managers/fileSaver/download.ts
WebClients/applications/drive/src/app/managers/fileSaver/downloadSW.ts
WebClients/applications/drive/src/app/managers/fileSaver/README.md
```

Drive chooses among:

- in-memory Blob download
- Origin Private File System (OPFS)
- streaming Service Worker download

Selection logic:

- QA can force `memory`, `opfs`, or `sw` with the `DriveE2EDownloadMechanism` cookie.
- small downloads use memory.
- large downloads prefer OPFS when supported and quota is sufficient.
- Service Worker streaming is the fallback when available.
- memory fallback is last resort.

Relevance for the Go client:

- large file downloads should avoid full in-memory buffering.
- download code needs feature/capability gates.
- storage quota and temporary file cleanup need first-class handling.
- progress, cancellation, and failure reporting should be designed early.

## Verify App And Human Verification

Important files:

```text
WebClients/applications/verify/src/app/Verify.tsx
WebClients/applications/verify/src/app/broadcast.ts
WebClients/applications/verify/src/app/types.ts
```

The Verify app emits broadcast messages including:

```text
HUMAN_VERIFICATION_SUCCESS
CLOSE
ERROR
LOADED
RESIZE
```

For CAPTCHA and ownership verification, success messages include:

```text
payload: { token, type }
```

Relevance for the Go client:

- Proton login can require human verification.
- The Go client needs a designed UX for CAPTCHA/verification.
- If the app is GUI-based, it may need a webview or browser handoff for hCaptcha-like flows.
- If the app is CLI-based, it needs an alternate verification strategy or clear unsupported-state handling.

## Account App

Important files:

```text
WebClients/applications/account/src/pages/drive.login.ts
WebClients/applications/account/src/pages/login.ts
WebClients/applications/account/src/app/
```

The Account app is broad and supports many Proton products. For this project, the useful reference is the Drive login flow, session bootstrap assumptions, and human verification handoff.

## Crypto Worker Setup

Important file:

```text
WebClients/packages/shared/lib/helpers/setupCryptoWorker.ts
```

Behavior:

- If worker/module support is unavailable, WebClients dynamically imports the crypto API on the main thread.
- Otherwise, it initializes `CryptoWorkerPool` and routes `CryptoProxy` through that worker pool.

Relevance for the Go client:

- Go will not use the browser crypto worker model.
- The equivalent concern is keeping cryptographic operations isolated, bounded, cancellable, and safe with respect to memory handling.
- Any GUI should avoid blocking the UI thread during encryption/decryption.

## Build Implications

WebClients is a large Yarn workspace. Building selected apps requires:

- Node matching the root `engines`.
- Yarn 4 from the repository.
- access to public npm packages.
- handling Proton-internal package or registry assumptions if building outside Proton infrastructure.

The Go branch should not depend on WebClients builds unless the architecture explicitly changes.

## Practical Takeaways For The Go Client

- Treat authentication, human verification, file listing, and transfer operations as separate subsystems.
- Design human verification before promising fully automated login.
- Use streaming file transfers; avoid full-file buffering for large downloads.
- Keep local metadata and cache encryption separate from Proton's cloud encryption.
- Document which security properties come from Proton and which come from local code.
- Keep WebClients reference docs separate from Go implementation docs.
