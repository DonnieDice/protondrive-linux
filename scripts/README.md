# Scripts Directory

Build scripts, utilities, and helper scripts for protondrive-linux development and CI.

---

## Python Scripts

### `create_stubs.py`

**Purpose**: Creates stub npm packages for private Proton modules that aren't published on the public npm registry. When yarn encounters `@proton/collect-metrics` or `@proton/proton-foundation-search` as dependencies, those packages don't exist on npmjs.org — this script places minimal `package.json` + `index.js` stubs under `WebClients/node_modules/` so the build resolves them locally.

**When to run**: AFTER `yarn install` in WebClients, BEFORE the build step.

**Prerequisites**: `WebClients/` directory must exist with a completed `yarn install`. Run from the repository root.

**Example**:
```bash
python3 scripts/create_stubs.py
```

### `fix_deps.py`

**Purpose**: Prepares the WebClients monorepo for a CI/build-environment build by:
1. Stripping problematic dependencies (rowsnColumns, proton-meet, electron, proton-foundation-search) from all `package.json` files — these are Proton-internal or irrelevant to the desktop build.
2. Patching the Drive app's `build:web` script: switches from `--appMode=sso` to `--appMode=standalone` (SSO expects Proton's domain; standalone works with any origin like `tauri://`), removes any `--api` flag (Tauri IPC handles API calls), and adds `--no-sri` (WebKitGTK rejects script integrity on `tauri://` protocol).
3. Disabling SRI for the Account and Verify apps for the same WebKitGTK reason.
4. Configuring `.yarnrc.yml` — strips internal Proton registry config (npmScopes/npmRegistries), sets the public npm registry, and disables immutable installs.

**When to run**: BEFORE `yarn install` in WebClients, after cloning.

**Prerequisites**: `WebClients/` directory must exist (cloned from GitHub).

**Example**:
```bash
python3 scripts/fix_deps.py
```

### `patch_drive_linux_drawer.py` *(not yet created)*

**Purpose**: *(planned)* Will patch the Proton Drive Linux navigation drawer/rail into the WebClients UI. This script would modify the WebClients source to add a Linux-native sidebar/drawer component for the Tauri desktop wrapper.

**When to run**: *(TBD — after scripts are created)*

**Prerequisites**: `WebClients/` must exist with a completed `yarn install`.

### `patch_drive_linux_sync_bridge.py` *(not yet created)*

**Purpose**: *(planned)* Will inject the `ProtonDriveLinuxSyncBridge.tsx` component into the WebClients Drive application. This script would add the sync status UI and native sync bridge integration for the Linux desktop build.

**When to run**: *(TBD — after scripts are created)*

**Prerequisites**: `WebClients/` must exist with a completed `yarn install`.

---

## Shell Scripts

### `build-webclients.sh`

**Purpose**: Full automated build pipeline for WebClients — clones or refreshes the WebClients checkout, runs `fix_deps.py` and `create_stubs.py`, applies git patches from `patches/common/`, runs `yarn install`, builds all three apps (Drive, Account, Verify) in parallel, copies Account and Verify dist into Drive's dist directory with path fixups, strips SRI hashes from all dist files, and verifies build output.

**Usage**:
```bash
./scripts/build-webclients.sh
```

**Prerequisites**: Python 3, Node.js, yarn. Internet access for cloning WebClients and installing npm dependencies.

### `run-command.sh`

**Purpose**: Wrapper script for running npm commands without terminal lockup. Prevents the terminal from freezing when running Electron in development mode.

**Usage**:
```bash
./scripts/run-command.sh "npm start"
./scripts/run-command.sh "npm test"
```

---

## CI Scripts (`scripts/ci/`)

`scripts/ci/` is for reusable CI, packaging, install, transfer, VM test, and
release helper logic. Executable test cases live under `tests/` instead:
`tests/regression/`, `tests/unit/`, and `tests/robot/`.

| Script | Purpose |
|---|---|
| `build-alpine-320-apk.sh` | Build Alpine Linux 3.20 .apk package |
| `build-alpine-322-apk.sh` | Build Alpine Linux 3.22 .apk package |
| `build-alpine-323-apk.sh` | Build Alpine Linux 3.23 .apk package |
| `build-aur-package.sh` | Build Arch Linux AUR package |
| `build-opensuse-tumbleweed-rpm.sh` | Build openSUSE Tumbleweed .rpm package |

---

## Related Documentation

- [Project README](../README.md)
- [AGENTS.md](../AGENTS.md)
- [Patches README](../patches/README.md)

---

**Last Updated**: 2026-05-28
