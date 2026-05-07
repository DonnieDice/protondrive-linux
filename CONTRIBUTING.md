# Contributing

Thanks for helping improve Proton Drive Linux. This project is a Linux desktop wrapper around Proton WebClients, so correctness depends on keeping Rust/Tauri behavior, WebClients build behavior, and package workflows aligned.

## Project Ground Rules

- Keep the core app behavior shared across package formats.
- Put package-specific differences in packaging metadata, scripts, workflow setup, or runtime environment configuration.
- Keep local build scripts and GitHub Actions equivalent when they touch the same behavior.
- Prefer Tauri 2 conventions and capability permissions.
- Treat Proton WebClients as upstream code. Changes to WebClients should be carried as documented patches unless there is a deliberate reason to fork behavior.

## Local Setup

Clone this repository and create the local WebClients checkout:

```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
git clone --depth=1 --single-branch --branch main \
  https://github.com/ProtonMail/WebClients.git WebClients
npm install
```

Build the web assets:

```bash
npm run build:web
```

Run the app:

```bash
npm run dev
```

## Repository Areas

Rust/Tauri:

```text
src-tauri/src/main.rs
src-tauri/tauri.conf.json
src-tauri/capabilities/default.json
```

Build and release automation:

```text
scripts/
.github/workflows/
Makefile
package.json
```

Packaging:

```text
src-tauri/linux/
aur/
snap/
```

Documentation:

```text
README.md
docs/
```

## Development Workflow

1. Create a feature branch.
2. Make the smallest change that solves the issue.
3. Update docs when behavior, commands, package expectations, or troubleshooting steps change.
4. Run focused verification.
5. Include the verification results in your PR.

Example:

```bash
git checkout -b fix/download-filename
make fmt
make lint
```

## Verification

For Rust-only changes:

```bash
make fmt
make lint
```

For build script or WebClients integration changes:

```bash
npm run build:web
```

For packaging changes, build the affected package:

```bash
npm run build:deb
npm run build:rpm
npm run build:appimage
```

For release workflow changes, inspect the matching GitHub Actions YAML and the local script that performs the same work.

## WebClients Patches

Use patches for changes that must be applied to upstream WebClients during builds.

Shared patches belong in:

```text
patches/common/
```

Create a patch from inside a modified `WebClients/` checkout:

```bash
cd WebClients
git diff > ../patches/common/descriptive-name.patch
```

Then test:

```bash
cd ..
npm run build:web
```

## Version Changes

Update `package.json` first, then sync:

```bash
scripts/sync-version.sh
```

Confirm the expected version in:

- `package.json`
- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `aur/PKGBUILD`, if applicable

## Pull Request Checklist

- The change is scoped to the relevant behavior.
- Local and CI build paths remain aligned.
- Documentation is updated for changed behavior.
- Package-specific behavior is not hidden in shared runtime code unless that is intentional and documented.
- Verification commands and results are included in the PR description.

## Useful References

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Build and Release](docs/build-and-release.md)
- [Packaging](docs/packaging.md)
- [Multi-Agent Coordination](docs/multi-agent-coordination.md)
- [Troubleshooting](docs/troubleshooting.md)
