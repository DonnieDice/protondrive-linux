# Development

This guide is for local development on Linux.

## Local Setup

Clone this repository:

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
```

Clone Proton WebClients into the root of this repository:

```bash
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
```

Install root dependencies:

```bash
npm install
```

Build the embedded web app:

```bash
npm run build:web
```

Start Tauri:

```bash
npm run dev
```

## What `npm run build:web` Does

`scripts/build-webclients.sh` performs the local WebClients build:

1. Runs `scripts/fix_deps.py`.
2. Applies patches from `patches/common`.
3. Installs WebClients dependencies with Proton's checked-in Yarn 4 release.
4. Builds the `proton-drive` web app.
5. Builds the `proton-account` app when possible.
6. Builds the `proton-verify` app when possible.
7. Copies Account and Verify builds into Drive's `dist` directory.
8. Rewrites nested asset paths.
9. Verifies the final `applications/drive/dist` output.

## Editing Areas

Rust/Tauri desktop behavior:

```text
src-tauri/src/main.rs
src-tauri/tauri.conf.json
src-tauri/capabilities/default.json
```

Build automation:

```text
scripts/
.github/workflows/
Makefile
package.json
```

Packaging:

```text
src-tauri/tauri.conf.json
src-tauri/linux/
aur/
snap/
```

WebClients compatibility:

```text
patches/
scripts/fix_deps.py
scripts/create_stubs.py
```

## Formatting and Linting

Format Rust:

```bash
make fmt
```

Run Clippy:

```bash
make lint
```

Run WebClients tests if WebClients dependencies are installed:

```bash
make test
```

## Keeping Local and CI Equivalent

Local builds use an existing `WebClients/` directory. CI clones WebClients fresh.

When changing any of these, check both local scripts and GitHub Actions:

- WebClients clone branch or commit.
- Dependency patching.
- WebClients Yarn install flags.
- Account/Verify copying.
- Asset path rewrites.
- Bundle targets.
- Linux system dependencies.
- Version sync behavior.

The goal is that local behavior and CI behavior produce equivalent application assets even though they get WebClients from different starting states.

## Version Updates

The canonical version is `package.json`.

Sync dependent files:

```bash
scripts/sync-version.sh
```

This updates:

- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `aur/PKGBUILD`, when present

## Common Gotchas

- `WebClients/` is not a Git submodule in the current repository state.
- `npm run dev` expects `WebClients/applications/drive/dist` to exist.
- `scripts/setup.sh` initializes submodules, but there is currently no `.gitmodules` file. Clone WebClients manually for local work.
- PowerShell cannot run shell scripts directly without WSL, Git Bash, MSYS2, or another bash environment.
- Proton WebClients changes frequently. A build failure can be caused by upstream changes, not only this repository.
