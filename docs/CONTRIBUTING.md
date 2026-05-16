# Contributing to Proton Drive Linux

Thank you for your interest in contributing. This guide covers the current repo
layout, build flow, and packaging rules.

## Project Structure

```text
protondrive-linux/
|-- src-tauri/            # Rust backend and Tauri configuration
|   |-- src/main.rs
|   |-- Cargo.toml
|   `-- tauri.conf.json
|-- WebClients/           # Cloned at build time, not tracked as a submodule
|-- patches/              # Target-specific patches
|-- scripts/              # WebClients build helper and CI scripts
|-- packaging/            # Compatibility map and package templates
|-- docs/                 # Documentation
`-- aur/                  # AUR PKGBUILD
```

## Setup

Clone the repository:

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
```

Clone WebClients when building locally:

```bash
git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients
```

Install JavaScript and Rust dependencies:

```bash
npm install
rustup update
```

Install system dependencies for your distribution:

```bash
# Fedora
sudo dnf install webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel openssl-devel

# Debian / Ubuntu
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev libssl-dev

# Arch / Manjaro
sudo pacman -S webkit2gtk-4.1 gtk3 libayatana-appindicator
```

## Development

For web app changes, edit files under `WebClients/applications/drive/src/`.

For desktop features, edit `src-tauri/src/main.rs` and restart the dev server.
Do not add distro-specific WebKitGTK env vars or runtime behavior in
`main.rs`; those belong in `patches/`. `DISTRO_TYPE` is only for package-type
diagnostics.

For configuration, edit `src-tauri/tauri.conf.json`.

Run locally:

```bash
npm run dev
```

## Building

Remote GitHub Actions workflows are the source of truth for release artifacts.
Local builds are useful for debugging compilation only:

```bash
npm run build:web
cd src-tauri
cargo build --release
```

The package workflows under `.github/workflows/` produce release artifacts.
See `docs/packaging.md` for the release gate.

## Packaging Rules

- Name patches by ABI/runtime target, not distro branding.
- Keep WebKitGTK env vars, sandbox flags, renderer flags, and distro-specific
  runtime behavior in `patches/<package>/<target>.patch`.
- Use `patches/common/` only for changes needed by every package.
- Add release targets or roadmap patch-ready targets to
  `packaging/compatibility-map.yml`.
- Promote a roadmap patch-ready target to release-gated only after a package
  workflow, artifact upload, release integration, and runtime smoke test exist.

See `docs/packaging.md` for details.

## Adding a Desktop Command

Add the Rust command in `src-tauri/src/main.rs`:

```rust
#[tauri::command]
async fn my_new_command(param: String) -> Result<String, String> {
    Ok(format!("Processed: {}", param))
}
```

Register it in `tauri::generate_handler![...]`, then call it from the web app:

```typescript
import { invoke } from "@tauri-apps/api/core";

const result = await invoke("my_new_command", { param: "test" });
```

## Testing

Manual testing:

1. Run `npm run dev`.
2. Test the app window, login flow, downloads, dialogs, and notifications.
3. Check terminal logs for Tauri/WebKitGTK errors.

Web app tests live in WebClients:

```bash
cd WebClients/applications/drive
npm test
```

## Updating WebClients

WebClients is cloned at build time. To change the branch or checkout depth,
edit `scripts/build-webclients.sh`, then re-run the build.

## Submitting Changes

Create a branch:

```bash
git checkout -b feature/my-feature
```

Commit with a clear, linkable title:

```bash
git commit -m "Add system tray icon support (#123)"
```

Use the issue number in the title when the commit is not itself a squash-merge
PR title. If the work is not tracked yet, open an issue first and use that
number. Do not leave the commit title without a GitHub reference.

If you also want body traceability, reference the issue in the body or footer:

```bash
git commit -m "Add system tray icon support" -m "Refs #123"
```

Use `Closes #123` when the commit fully resolves the issue.

Push and open a pull request:

```bash
git push origin feature/my-feature
```

### PR Title Format

All PR titles must match the CommitCheck regex: `^[A-Z].{9,}\s\(#\d+\)$`

Rules:

- Start with an uppercase letter
- Be at least 10 characters long (before the PR number)
- End with the PR number in parentheses, e.g. `(#42)`

Examples:

- `Add Alpine 3.20 APK build target (#47)`
- `Fix linker flags for musl static linking (#51)`
- `Update WebClients clone depth in build script (#38)`

Edit the PR title after GitHub assigns the PR number (it appears in the
URL and page header immediately after creation). Dependabot PRs will need
their titles updated before merging if they don't conform.

### Commit Message and Link Rules

- Use the commit title for a clear imperative summary plus an issue number
  suffix when the commit is not a squash-merge PR title.
- Use the commit body or footer for extra traceability if needed
  (`Refs #123` or `Closes #123`).
- Use the PR title for the PR number suffix (`... (#123)`).
- Do not link file diffs or fake PR numbers in commit titles.
- If there is no issue yet, create one before writing the commit title.

## Troubleshooting

Update Rust and dependencies:

```bash
rustup update
cd src-tauri
cargo update
```

Clone WebClients if it is missing:

```bash
git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients
```

Node.js 20+ is required:

```bash
node -v
```

## Need Help?

- [Tauri Documentation](https://tauri.app/)
- [Proton WebClients](https://github.com/ProtonMail/WebClients)
- Open an issue with build logs and the target distro/runtime
