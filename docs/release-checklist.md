# Release Checklist

Use this checklist before every release deployment.

## Required Pre-Release Checks

- [ ] Version bump is complete.
  - [ ] `package.json` contains the release version.
  - [ ] Synced package metadata uses the same version.
  - [ ] Any package-specific version files are updated.

- [ ] Documentation update is complete.
  - [ ] User-facing docs reflect the release behavior.
  - [ ] Packaging/support docs reflect current release-gated targets.
  - [ ] Install, build, and troubleshooting docs are updated where needed.

- [ ] This release checklist is checked and updated.
  - [ ] `docs/release-checklist.md` still matches the current release process.
  - [ ] New release tasks discovered during this cycle are added before tagging.
  - [ ] Obsolete release tasks are removed or corrected.

- [ ] Release job includes all `pass` status packages.
  - [ ] `.github/workflows/package-workflows.yml` includes every package marked as release-gated with `pass` runtime smoke status in `packaging/compatibility-map.yml`.
  - [ ] Roadmap, legacy candidate, and not-primary targets are excluded unless promoted.
  - [ ] Release artifacts use stable, unique names.

- [ ] All builds are green in GitHub Actions.
  - [ ] AppImage linux-baseline job is passing.
  - [ ] Debian 12, Debian 13, Ubuntu 24.04, and Ubuntu 26.04 DEB jobs are passing.
  - [ ] Fedora 43, Fedora 44, EL10, and openSUSE Tumbleweed RPM jobs are passing.
  - [ ] Flatpak GNOME 49 and GNOME 50 jobs are passing.
  - [ ] Snap core24 and core26 jobs are passing.
  - [ ] AUR Arch Native job is passing.
  - [ ] Alpine 3.20, 3.22, and 3.23 APK jobs are passing.
  - [ ] Release job is passing.
- [ ] Publish implementation secrets are configured.
  - [ ] `AUR_SSH_PRIVATE_KEY` secret is set for AUR publishing.
  - [ ] `SNAPCRAFT_STORE_CREDENTIALS` secret is set for Snap Store publishing. **BLOCKED: snapcraft CLI / Snap Store API inconsistency — publishing on hold. See issues #83 and #19.**
  - [ ] `FLATHUB_SSH_PRIVATE_KEY` secret is set for Flathub publishing.
  - [ ] Flathub initial submission PR has been merged (required before the Flatpak publish implementation can push updates).

- [ ] Merge approved PRs into `main`.
  - [ ] Confirm the PRs contain only commits intended for the release.
  - [ ] Never bypass review by pushing release changes directly.
  - [ ] Push `main` after the merge.

## Final Release Gate

Do not tag or publish a release until every checkbox above is complete.

The release tag must point to `main`.
