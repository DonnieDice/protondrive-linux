# Contributing to Proton Drive Linux

Thank you for your interest in contributing. This guide covers the current repo
layout, dev prerequisites, build flow, packaging rules, and PR workflow.

## Project Structure

```text
protondrive-linux/
|-- src-tauri/            # Rust backend and Tauri configuration
|   |-- src/main.rs
|   |-- Cargo.toml
|   |-- tauri.conf.json
|   |-- icons/             # App icons for all package formats
|   `-- linux/             # Desktop integration files (.desktop, etc.)
|-- WebClients/           # Cloned at build time, not tracked as a submodule
|-- patches/              # Target-specific patches
|   |-- common/            # Source changes required by every package
|   |-- appimage/
|   |-- aur/
|   |-- deb/
|   |-- rpm/
|   |-- apk/
|   |-- flatpak/
|   |-- snap/
|   |-- nix/              # Roadmap
|   |-- gentoo/           # Roadmap
|   `-- slackware/        # Roadmap
|-- scripts/              # WebClients build helper and CI scripts
|-- packaging/            # Compatibility map and package templates
|-- docs/                 # Documentation
|-- .github/              # GitHub Actions workflows and issue templates
|-- .gitlab-ci.yml        # GitLab CI pipeline (mirrored)
`-- aur/                  # AUR PKGBUILD
```

## Prerequisites

### Node.js

Node.js **20+** is required. The build scripts enforce this automatically —
running `npm install` or any `npm run` command will fail with a clear message
if your Node.js is too old.

```bash
node -v   # must be >= 20.0.0
```

If you need to upgrade, use [nvm](https://github.com/nvm-sh/nvm) or your
distribution's package manager.

### Rust

Install Rust via [rustup](https://rustup.rs/):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustup update stable
```

Do not use your distribution's system `rustc`/`cargo` packages — they are
typically too old for Tauri 2 development. Always use rustup.

### System Dependencies

Install WebKitGTK 4.1 + GTK 3 + appindicator libraries:

```bash
# Fedora
sudo dnf install webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel openssl-devel

# Debian / Ubuntu
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev libssl-dev

# Arch / Manjaro
sudo pacman -S webkit2gtk-4.1 gtk3 libayatana-appindicator

# Alpine
sudo apk add webkit2gtk-4.1-dev gtk+3.0-dev libayatana-appindicator-dev
```

> **Note:** Alpine requires additional transitive dev packages. See
> `docs/new-build-checklist.md` for the full Alpine dependency list including
> `glib-dev`, `harfbuzz-dev`, `cairo-dev`, `pango-dev`, `gdk-pixbuf-dev`,
> `wayland-dev`, `zlib-dev`, `libintl`, `musl-dev`, and `libsoup3-dev`.

## Setup

Clone the repository:

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
```

Clone WebClients when building locally:

```bash
git clone --depth=1 --single-branch --branch main \
    https://github.com/ProtonMail/WebClients.git WebClients
```

Install JavaScript dependencies:

```bash
npm install
```

## Development

For web app changes, edit files under `WebClients/applications/drive/src/`.

For desktop features, edit `src-tauri/src/main.rs` and restart the dev server.
Do not add distro-specific WebKitGTK env vars or runtime behavior in
`main.rs`; those belong in `patches/`. `DISTRO_TYPE` is only for package-type
diagnostics.

For configuration, edit `src-tauri/tauri.conf.json`.

Run the development server:

```bash
npm run dev
```

## Building

GitLab CI is the authoritative build, package, VM-test, signing, and release
system. The GitHub repository is a public mirror/community surface; GitHub
Actions are intentionally limited to public sanity checks plus explicit manual
maintenance workflows so mirrored commits do not duplicate the full CI/CD
pipeline.

Local builds are useful for debugging compilation only:

```bash
npm run build:web
```

This runs `scripts/build-webclients.sh`, which:
1. Patches WebClients dependencies via `scripts/fix_deps.py`
2. Applies common patches from `patches/common/`
3. Installs WebClients dependencies
4. Creates stubs for private Proton npm packages
5. Builds Drive, Account, and Verify apps in parallel
6. Copies Account and Verify dist into the Drive dist folder
7. Fixes nested asset paths and strips SRI hashes for WebKitGTK compatibility

### Build the native binary and packages

```bash
# Full build (deb + rpm + appimage)
npm run build

# Individual bundle types
npm run build:deb       # DEB only
npm run build:rpm       # RPM only
npm run build:appimage  # AppImage only

# Or build only the binary (for APK targets, etc.)
cd src-tauri
cargo build --release
```

The package workflow implementations under `.github/workflows/` are retained for
manual compatibility checks and maintenance, but release artifacts should be
produced and published by GitLab CI unless the CI authority is intentionally
changed. See `docs/packaging.md` for the release gate.

## Packaging Rules

- Name patches by ABI/runtime target, not distro branding.
- Keep WebKitGTK env vars, sandbox flags, renderer flags, and distro-specific
  runtime behavior in `patches/<package>/<target>.patch`.
- Use `patches/common/` only for changes needed by every package.
- Add release targets or roadmap patch-ready targets to
  `packaging/compatibility-map.yml`.
- Promote a roadmap patch-ready target to release-gated only after a package
  workflow, artifact upload, release integration, and runtime smoke test exist.
- See `docs/packaging.md` for the full compatibility gate model (glibc +
  WebKitGTK) and support matrix.
- See `docs/new-build-checklist.md` for the step-by-step process of adding
  a new package target.

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

### Manual testing

1. Run `npm run dev`.
2. Test the app window, login flow, downloads, dialogs, and notifications.
3. Check terminal logs for Tauri/WebKitGTK errors.

### Web app tests

Web app tests live in WebClients:

```bash
cd WebClients/applications/drive
npm test
```

### Automated dependency updates

Dependabot is configured under `.github/dependabot.yml` for weekly updates on:
- **Cargo** (Rust dependencies in `src-tauri/`)
- **npm** (JavaScript dependencies in root `package.json`)
- **GitHub Actions** (workflow dependencies)

Dependabot opens PRs with the `dependencies` label. Review and merge these
like any other PR — they include automatic changelogs and version bumps.

## Updating WebClients

WebClients is cloned at build time. To change the branch or checkout depth,
edit `scripts/build-webclients.sh`, then re-run the build.

The CI pipeline pins WebClients in two ways:
- **GitLab CI** uses `WEBCLIENTS_REF` (branch) and `WEBCLIENTS_COMMIT` (pinned
  commit hash via `git fetch --depth=1 origin <commit>`).
- **GitHub Actions** uses `WEBCLIENTS_REF=main` via `--branch main`.

When you update the pinned commit, update it in both `.gitlab-ci.yml` and the
applicable GitHub Actions composite actions.

## CI / Build Pipelines

This project runs **two CI systems** in parallel:

### GitHub Actions (primary)

The main CI system at `.github/workflows/package-workflows.yml` handles all
package builds (AppImage, DEB, RPM, Flatpak, Snap, APK, AUR), spec generation,
release packaging, and publishing. Workflows trigger on pushes to `main`,
`feature/**`, `fix/**`, `chore/**` branches, tags, and PRs targeting `main`.

Package implementations live as local composite actions under
`.github/workflows/<package>/<target>/action.yml`. See `docs/packaging.md`
for the full layout.

### GitLab CI (mirrored)

A parallel pipeline at `.gitlab-ci.yml` provides identical build jobs for the
mirrored repository. It is kept in sync with the GitHub Actions workflow.
Changes to the build process should be mirrored in both CI configurations.

The `.github/workflows/sync-to-gitlab.yml` workflow mirrors GitHub to GitLab
on every push to `main`.

### CI Jobs

| Job group | Triggers on |
|-----------|-------------|
| Package builds (AppImage, Flatpak, Snap, DEB, RPM, APK, AUR) | Push to `main`, `feature/**`, `fix/**`, `chore/**` + tags + PRs to `main` |
| Generate package specs | Same as package builds |
| Release | Release publication and release-tag flow |
| Publish AUR, Snap, Flatpak | Release events and manual dispatch |
| Sync to GitLab | Push to `main` |

### Release Checklist

See `docs/release-checklist.md` for the full release process including version
bumps, build verification, CI checks, publishing secrets, and post-release
verification.

## Submitting Changes

### Create an issue first

Open a [GitHub issue](https://github.com/DonnieDice/protondrive-linux/issues)
for every bug, feature request, or task before writing code. Issues:

- Track what's open/done.
- Link commits and PRs back to intent (`Closes #42` auto-closes on merge).
- Discuss the _why_ before touching code.

Issue templates are available for:
- **Bug reports** — includes fields for distro, version, package format, steps
- **Feature requests** — includes problem, solution, alternatives, scope
- **Questions** — includes topic and free-form question

### Branch naming

One branch per issue, named to make the connection explicit:

| Prefix | Use case | Example |
|--------|----------|---------|
| `feature/` | New functionality | `feature/42-add-login-page` |
| `fix/` | Bug fixes | `fix/87-broken-csv-export` |
| `chore/` | Non-code work (docs, deps, CI) | `chore/103-update-dependencies` |

Never work directly on `main`. No intermediate branches (no `alpha`). All
feature branches merge directly to `main`.

### Commit messages

```bash
git commit -m "(#123) Add system tray icon support"
```

The number in the commit title is the **issue** number (e.g., `#123`), not the
PR number. If the work is not tracked yet, open an issue first and use that
number. Do not leave the commit title without a GitHub reference.

Rules:
- Start with an uppercase letter.
- Be at least 10 characters long (after the issue number prefix).
- Use `Closes #123` in the body/footer when the commit fully resolves the issue.

### Push and open a PR

```bash
git checkout -b feature/my-feature
git commit -m "(#123) Add system tray icon support"
git push origin feature/my-feature
```

### PR Title Format

PR titles must match the CommitCheck regex: `^\(\#\d+\)\s[A-Z].{9,}$`

Rules:
- The number in the PR title is the **PR** number, not the tracked issue number.
- Start with an uppercase letter after the PR prefix.
- Be at least 10 characters long after the PR prefix.

Examples:
- `(#48) Add Alpine 3.20 APK build target`
- `(#52) Fix linker flags for musl static linking`
- `(#39) Update WebClients clone depth in build script`

If GitHub has not assigned the PR number yet, create the PR first, then edit
the title once the number exists.

### PR Body Format

Reference the tracked issue at the top. Use `Closes #N` when the PR fully
resolves the issue, or `Refs #N` for partial work:

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

### Review Bot Feedback

Before merging **any** PR, all automated review bot findings must be addressed:

- Check CodeRabbit, Qodo, and any other review bot comments on the PR.
- Every actionable comment must be either **fixed** or explicitly **dismissed
  with justification**.
- Do not merge with unresolved bot review items — even if CI passes.
- If a bot comment is a false positive, dismiss it on the PR conversation so
  it is documented.
- Re-request review after pushing fixes to ensure bots re-evaluate.

## Security

Vulnerabilities must **not** be reported through public GitHub issues. Use
GitHub's private vulnerability reporting feature:

1. Navigate to the repository's **Security** tab.
2. Click **Report a Vulnerability** in the left sidebar.
3. Fill out the form with as much detail as possible.

See `docs/SECURITY.md` for the full security policy, including response
commitments and the known upstream Dependabot alert.

## Code of Conduct

All contributors must follow the project's
[Code of Conduct](CODE_OF_CONDUCT.md). Report unacceptable behavior by
opening a GitHub issue — see the CoC for details.

## Need Help?

- [Tauri Documentation](https://tauri.app/)
- [Proton WebClients](https://github.com/ProtonMail/WebClients)
- [Project Issues](https://github.com/DonnieDice/protondrive-linux/issues)
- Open an issue with build logs and the target distro/runtime
