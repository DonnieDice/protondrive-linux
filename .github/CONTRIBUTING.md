# Contributing to ProtonDrive Linux

> **📍 This is a public mirror.** All development happens on the
> [self-hosted GitLab instance](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux).
> Please open issues and merge requests there — contributions submitted as GitHub Pull Requests
> are automatically synced to GitLab via the
> [sync-to-gitlab workflow](workflows/sync-to-gitlab.yml), where CI runs the full
> build and install matrix before any merge.

## Where to contribute

| Action | Where |
|--------|-------|
| Open an issue | [GitLab Issues](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux/-/issues) (preferred) or GitHub Issues (auto-synced) |
| Submit a fix or feature | [GitLab Merge Request](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux/-/merge_requests) (preferred) or GitHub PR (auto-synced to GitLab) |
| Browse CI pipelines | [GitLab CI](https://gitlab.dicematrix.cloud/DonnieDice/protondrive-linux/-/pipelines) — full package builds and VM matrix |
| Lightweight checks | [GitHub Actions](https://github.com/DonnieDice/protondrive-linux/actions) — login/sync regression and Rust unit tests only |

## Development guide

See [docs/CONTRIBUTING.md](../docs/CONTRIBUTING.md) for the full guide covering:

- Project structure and build setup
- Tauri + WebKit development workflow
- Packaging rules (APK, DEB, RPM, AUR, Flatpak, Snap, AppImage)
- Branch and merge policy
- CI authority — what runs where and why

## CI policy summary

Full package builds and release artifacts are **only produced by GitLab CI**. GitHub Actions
run three lightweight jobs on every PR and push:

1. **Login/2FA routing regression** — guards navigation invariants
2. **Sync regression** — guards sync bridge invariants
3. **Rust unit tests** — `cargo test` for cookie, login, and live-sync modules

These checks are fast (< 30 min total) and do not build or publish packages.
See [docs/ci-authority-and-mirroring.md](../docs/ci-authority-and-mirroring.md) for the full
CI authority policy.
