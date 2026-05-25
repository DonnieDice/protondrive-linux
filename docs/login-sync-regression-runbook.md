# Login And Sync Regression Runbook

This runbook covers the recurring regressions that cannot be fully proven in
container CI because they need Proton Account, 2FA, WebKitGTK persistence, and a
real desktop session. CI must still guard the static contracts and unit tests
listed here so risky changes are visible before manual acceptance testing.

## CI Guardrails

Run these checks before packaging or manual acceptance:

```bash
bash scripts/ci/check-login-routing-regressions.sh
bash scripts/ci/check-sync-regressions.sh
cd src-tauri && cargo test proton_navigation::tests webview_cookies::tests live_sync::tests
```

The CI checks do not use real Proton credentials. They guard:

- Post-2FA handoff goes to `tauri://localhost/`, not a deep `/u/<id>/` Tauri URL.
- CAPTCHA completion is accepted only from `tauri://localhost/account/?hv_token=...&hv_type=...`.
- Drive restores `/u/<localID>/` from persisted `ps-<localID>` localStorage before app init.
- Host-only Proton auth cookies are scoped to the response host for restart persistence.
- Startup loading has user-facing diagnostics for WebView state and blocked proxy requests.
- All `proxy_request` IPC invokes are serialized through `invokeProxyRequest`/`proxyInvokeChain`.
  WebKitGTK's IPC custom protocol breaks under concurrent invoke load and falls back to
  postMessage, where JSON object responses never resolve. Direct
  `await window.__TAURI__.core.invoke('proxy_request', ...)` is forbidden — every API proxy
  call must go through the serialization queue or the loading screen will freeze.
- Sync commands stay registered and the native watcher emits `live-sync://local-change`.
- Remote sync payloads keep the `{ relativePath, action, contentBase64 }` contract.
- Default sync startup creates and watches `~/ProtonDrive` and maps it to `Computers/<PC name>`.

## Manual Login And 2FA Procedure

Use a disposable test account or an account approved for release testing. Select
`Keep me signed in` during login.

1. Start from a clean app process and capture logs.
2. Complete username/password login.
3. Complete 2FA.
4. Confirm Drive loads without freezing after the account handoff.
5. Quit the app completely.
6. Start the app again without re-entering credentials.
7. Confirm Drive restores the signed-in session and does not loop back to Account.

Expected positive markers:

- `[SSO] Login complete, redirecting to: tauri://localhost/`
- `window.location.replace('about:blank')` exists in the handoff code path.
- `[SSO] Restored Drive user route before app init: /u/<localID>/`
- `[STORAGE] pathname: /u/<localID>/ ... sessions: ps-<localID>`
- `[Cookie] stored name=AUTH-... domain=mail.proton.me path=/api/...`
- `[Cookie] stored name=REFRESH-... domain=mail.proton.me path=/api/auth/refresh...`
- `[Proxy][<id>] 200 <- https://mail.proton.me/api/auth/v4/sessions/local/key elapsed_ms=...`
- `[STARTUP_DIAG] [StartupDiag] startup watchdog 8s` if startup is still loading.
- A visible `protondrive-startup-diagnostics` panel appears if API proxy calls remain pending.

Expected negative markers:

- No repeated navigation between Account and Drive after 2FA.
- No final deep WebView reload to `tauri://localhost/u/<localID>/`.
- No `[CAPTCHA] Left captcha page, returning to account app`.
- No repeated post-login `/api/auth/v4/sessions/local/key` `401`.
- No repeated post-login `/api/auth/refresh` `422`.
- No `session-expired` loop after the restart test.
- No startup request remains pending past 30 seconds without a visible diagnostics panel.
- No native proxy request hangs indefinitely; failures must resolve as logged `502` or `504`.

## Manual Sync Procedure

Do not start with the full `~/Pictures` tree. Normal startup should create and
watch `~/ProtonDrive`. Use a disposable staged folder under that root first,
then expand only after the staged loop passes.

```bash
mkdir -p "$HOME/ProtonDrive/protondrive-sync-smoke/nested"
proton-drive
```

For override smoke tests, `PROTONDRIVE_AUTO_SYNC_PATH` may point at another
folder under `$HOME`; treat that as an extra mapping path, not the primary drive
root model. The Linux entry in the right-side Proton app rail opens the Drive
quick-settings drawer as the first Proton Drive Linux options surface. The rail
should preserve WebClients behavior: collapsed on startup with the
expand/collapse chevron visible; the dedicated sync UI should live there later,
not in the current folder route.

1. Confirm the native watcher and poll reconciler are active for `~/ProtonDrive`.
2. Create `local-create.txt` in the staged folder.
3. Confirm the local create event includes `relativePaths` for future remote-root mapping.
4. Modify `local-create.txt`.
5. Confirm the local modify event includes `source=watcher` or `source=poller`.
6. Delete `local-create.txt`.
7. Confirm the remove event is emitted.
8. Repeat create/modify/delete in `nested/`.
9. Create or update a small remote file under the synced folder.
10. Confirm frontend calls `handle_remote_update`.
11. Confirm native writes the local file and suppresses immediate ping-pong.
12. Delete the remote file.
13. Confirm native removes the local file.

Expected positive markers:

- `[Sync] selected root requested source=default` on normal startup.
- `[Sync] PROTONDRIVE_AUTO_SYNC_PATH requested` when using env override for extra mapping tests.
- `[Sync] selected root requested source=env` when using env override.
- `[Sync] auto-start active enabled=true folder=... poll_interval_seconds=...`.
- `[Sync] set_sync_root active enabled=true folder=... poll_interval_seconds=...` when using UI/command designation.
- `[Sync] get_sync_status enabled=true folder=...`.
- `[LiveSync] watcher active root=... mode=recursive`.
- `[LiveSync] poller active root=... interval_seconds=...`.
- `[LiveSync] local-change kind=create paths=... source=watcher` or `source=poller`.
- `[LiveSync] local-change kind=modify paths=... source=watcher` or `source=poller`.
- `[LiveSync] local-change kind=remove paths=... source=watcher` or `source=poller`.
- `live-sync://local-change` is observed by frontend handling.
- `[LiveSync][AUDIT] remote action=create result=success path=...` or `remote action=update`.
- `[LiveSync][AUDIT] remote action=delete result=success path=...`.

Expected negative markers:

- No test may be considered a sync pass from Drive/Photos API traffic alone.
- No silent window where file changes occur but no `[Sync]`, `[LiveSync]`, or
  `live-sync://local-change` markers appear.
- No `[Sync] auto-start failed`.
- No `[LiveSync] watcher init failed`.
- No `[LiveSync] watcher start failed`.
- No `[LiveSync] failed to emit local-change event`.
- No `[LiveSync][AUDIT] rejected remote write`.
- No `[LiveSync][AUDIT] rejected remote delete`.

## Pass Criteria

Login/session acceptance passes only when login, 2FA, app restart, and
keep-me-signed-in restore all complete with the positive markers above and none
of the negative loop markers.

Sync acceptance passes only when the staged local-to-remote and remote-to-local
loops both produce native sync markers. Authenticated Drive/Photos API activity
without `start_sync`, `get_sync_status`, `[Sync]`, `[LiveSync]`, or
`live-sync://local-change` is an inconclusive sync test and should be reported as
a regression-risk gap, not a pass.
