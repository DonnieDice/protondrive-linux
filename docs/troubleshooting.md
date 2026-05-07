# Troubleshooting

This page focuses on failures that are specific to this repository's architecture: Tauri, WebKitGTK, Proton WebClients, and Linux packaging.

## WebClients Directory Missing

Symptom:

```text
ERROR: WebClients directory not found
```

Fix:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Then rerun:

```bash
npm run build:web
```

## Drive Dist Missing

Symptom:

```text
dist directory not found
index.html not found in dist
```

The Tauri app expects:

```text
WebClients/applications/drive/dist/index.html
```

Fix:

```bash
npm run build:web
```

If that fails, inspect the first WebClients build error rather than the final Tauri error.

## White Screen or EGL Error

Symptoms:

```text
Could not create default EGL display: EGL_BAD_PARAMETER
```

or a blank/white app window.

Try:

```bash
GDK_GL=disable WEBKIT_DISABLE_DMABUF_RENDERER=1 ./proton-drive_*.AppImage
```

If needed:

```bash
GDK_GL=disable \
GSK_RENDERER=cairo \
WEBKIT_DISABLE_DMABUF_RENDERER=1 \
WEBKIT_DISABLE_COMPOSITING_MODE=1 \
WEBKIT_FORCE_SANDBOX=0 \
./proton-drive_*.AppImage
```

The Rust app sets similar variables at startup, and the CI AppImage `AppRun` also sets them. Some distribution/runtime combinations may still require testing with a different package format.

## Login Redirect Loops

Relevant paths:

- `src-tauri/src/main.rs`
- Account app output under `WebClients/applications/drive/dist/account`
- Drive app output under `WebClients/applications/drive/dist`

Check:

- Account app was built or copied.
- `account/index.html` has `<base href="/account/">`.
- Account app HTML does not contain `src="/assets/` or `href="/assets/`.
- Navigation logs show `/login` being rewritten to `tauri://localhost/account/`.

Rebuild:

```bash
npm run build:web
```

## CAPTCHA Does Not Complete

Relevant behavior:

- Proton 9001 human verification responses are detected in the injected fetch proxy.
- The app navigates to Proton's Verify page as a top-level document.
- hCaptcha domains are allowed by navigation handling.
- After leaving CAPTCHA, the app returns to the local Account app.

Check:

- `WebClients/applications/drive/dist/verify/index.html` exists when the Verify build succeeds.
- Verify app paths are rewritten to `/verify/assets/`.
- The app is allowed to reach `verify.proton.me`, `verify-api.proton.me`, and hCaptcha domains.

## Downloads Do Not Save

Downloads should save to `~/Downloads`.

Relevant code:

- `save_download` in `src-tauri/src/main.rs`
- injected `URL.createObjectURL`, `window.open`, anchor click, and `download` attribute hooks
- Tauri `on_download` handler

Check:

- The Downloads directory can be created or written.
- The app logs include `[Download]` entries.
- Blob URLs are captured in `window.__blobUrls`.

## WebClients Dependency Install Fails

The WebClients repository depends on Proton's monorepo tooling and may reference private/internal packages. This repository works around that by:

- removing problematic dependencies in `scripts/fix_deps.py`
- using the public npm registry
- disabling immutable installs
- creating private package stubs in CI with `scripts/create_stubs.py`

Local flow:

```bash
python3 scripts/fix_deps.py
cd WebClients
export NODE_OPTIONS="--max-old-space-size=8192"
node .yarn/releases/yarn-4.12.0.cjs install --network-timeout 300000
```

CI also runs:

```bash
python3 scripts/create_stubs.py
```

after install and before building.

## Tauri Build Cannot Find System Libraries

Install WebKitGTK and GTK development packages for your distribution.

Debian/Ubuntu:

```bash
sudo apt-get install -y libwebkit2gtk-4.1-dev libgtk-3-dev \
  libayatana-appindicator3-dev librsvg2-dev libsoup-3.0-dev
```

Fedora:

```bash
sudo dnf install -y webkit2gtk4.1-devel gtk3-devel \
  libayatana-appindicator-gtk3-devel librsvg2-devel libsoup3-devel
```

Arch:

```bash
sudo pacman -S --needed webkit2gtk-4.1 gtk3 libayatana-appindicator librsvg libsoup3
```

## Stale Version in Packages

The source version is `package.json`.

Run:

```bash
scripts/sync-version.sh
```

Then confirm:

- `package.json`
- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `aur/PKGBUILD`, if applicable

all have the expected version.
