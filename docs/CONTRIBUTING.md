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
git commit -m "(#123) Add system tray icon support"
```

The number in the commit title is the **issue** number (e.g., `#123`), not the
PR number. If the work is not tracked yet, open an issue first and use that
number. Do not leave the commit title without a GitHub reference.

If you also want body traceability, reference the issue in the body or footer:

```bash
git commit -m "(#123) Add system tray icon support" -m "Refs #123"
```

Use `Closes #123` when the commit fully resolves the issue.

Push and open a pull request:

```bash
git push origin feature/my-feature
```

### PR Body Format

Reference the tracked issue at the top. Use `Closes #123` when the PR fully
resolves the issue, or `Refs #123` for partial work:

```markdown
Closes #42

## Summary

- Describe the main behavior or packaging change
- Mention important files or workflow areas with plain paths

## Changed Areas

- `.github/workflows/package-workflows.yml`
- `.github/workflows/deb/debian-12/action.yml`
- `docs/packaging.md`

## Testing

- List the local commands or GitHub Actions runs used to verify the change
```

Do not add handcrafted GitHub `#diff-` anchors to PR bodies. They are easy to
break when files move or the PR is rebased. Plain repository paths are stable,
and reviewers can use the Files changed tab for exact diffs.

### PR Title Format

All PR titles must match the CommitCheck regex: `^\(#\d+\)\s[A-Z].{9,}$`

Rules:

- The number in the PR title is the tracked **issue** number, not the PR number
- Start with an uppercase letter after the issue prefix
- Be at least 10 characters long after the issue prefix
- Put the issue prefix at the start of the title, e.g. `(#42) Title here`

Examples:

- `(#47) Add Alpine 3.20 APK build target`
- `(#51) Fix linker flags for musl static linking`
- `(#38) Update WebClients clone depth in build script`

Open an issue before opening a PR when there is no tracked issue yet. This keeps
commits, PR titles, and closing links aligned from the first push.

### Review Bot Feedback

Before merging **any** PR, all automated review bot findings must be addressed:

- Check CodeRabbit, Qodo, and any other review bot comments on the PR
- Every actionable comment must be either **fixed** or explicitly **dismissed with justification**
- Do not merge with unresolved bot review items — even if CI passes
- If a bot comment is a false positive, dismiss it on the PR conversation so it is documented
- Re-request review after pushing fixes to ensure bots re-evaluate

### Commit Message and Link Rules

- Use the commit title for a clear imperative summary plus an **issue** number
  prefix when the commit is not a squash-merge PR title.
- Use the commit body or footer for extra traceability if needed
  (`Refs #123` or `Closes #123`).
- Use the PR title for the same **issue** number prefix (`(#123) ...`).
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
