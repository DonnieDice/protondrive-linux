# CI/CD Pipeline Writeup

This repository uses GitLab CI as the authoritative build and release system.
GitHub Actions remains available for public mirroring, issue/PR automation, and
manual compatibility checks, but it is not the release authority.

## Authority Model

GitLab owns:

- full package builds
- release artifact aggregation
- GitLab release creation
- VM/SSH smoke diagnostics
- publishing to AUR, Flathub, and Snap Store
- AI-assisted documentation audit jobs

GitHub owns:

- public contributor/mirror automation
- GitHub issue and PR synchronization into GitLab
- manual package workflow dispatches
- maintenance actions such as labels and package spec generation

The expected release provenance is:

```text
GitLab tag pipeline
  -> build all packages
  -> aggregate artifacts
  -> create GitLab release
  -> optionally publish to external stores
  -> optionally mirror artifacts to GitHub
```

GitHub must not independently rebuild and publish release artifacts unless the
project deliberately promotes GitHub to CI authority.

## GitLab Pipeline

The main pipeline is defined in `.gitlab-ci.yml` and includes
`.gitlab-ci-vm-tests.yml`.

Current stages:

```text
detect -> audit -> update -> build -> spec -> release -> publish
```

The first three stages are for the AI documentation audit path. The package
release path starts at `build`.

### Trigger Rules

The GitLab workflow is intentionally gated:

- Version tags matching `vX.Y.Z...` create release pipelines.
- Web/API pipelines run only when `RUN_RELEASE_TESTS=true`.
- Scheduled/web/API documentation audits run only when `RUN_DOC_AUDIT=true`.
- Ordinary branch pushes and merge requests do not create the full release
  pipeline by default.

This protects the self-hosted release runner and prevents accidental package
publishing from routine development activity.

### Shared Variables

Important shared variables:

- `RUST_VERSION=stable`
- `WEBCLIENTS_REF=main`
- `WEBCLIENTS_COMMIT=bbad1a0a482227b93a2e963a232463aede9b8abf`
- `CARGO_HOME=${CI_PROJECT_DIR}/.cargo`
- Docker-in-Docker variables for Snap and publish jobs
- `DOC_AUDIT_WINDOW_HOURS=24`

Build jobs repeatedly sync runtime versions from `package.json` into
`src-tauri/tauri.conf.json` and `src-tauri/Cargo.toml` before packaging.

## Build Matrix

All package build jobs extend `.rules:build`, run in the `build` stage, and
produce artifacts under `artifacts/`.

Current GitLab build jobs:

| Job | Target |
|---|---|
| `build:apk:alpine-3.20` | Alpine 3.20 APK-style tarball |
| `build:apk:alpine-3.22` | Alpine 3.22 APK-style tarball |
| `build:apk:alpine-3.23` | Alpine 3.23 APK-style tarball |
| `build:appimage` | Linux baseline AppImage |
| `build:aur` | Arch native package and AUR metadata |
| `build:deb:debian-12` | Debian 12 DEB |
| `build:deb:debian-13` | Debian 13 DEB |
| `build:deb:ubuntu-24.04` | Ubuntu 24.04 DEB |
| `build:deb:ubuntu-26.04` | Ubuntu 26.04 DEB |
| `build:flatpak:gnome-49` | Flatpak for GNOME runtime 49 |
| `build:flatpak:gnome-50` | Flatpak for GNOME runtime 50 |
| `build:rpm:el10` | EL10 RPM |
| `build:rpm:fedora-43` | Fedora 43 RPM |
| `build:rpm:fedora-44` | Fedora 44 RPM |
| `build:rpm:opensuse-tumbleweed` | openSUSE Tumbleweed RPM |
| `build:snap:core24` | Snap core24 |
| `build:snap:core26` | Snap core26 |

Most build jobs follow the same pattern:

```text
install distro dependencies
install Rust
clone WebClients
apply target-specific patch
build WebClients
sync version metadata
npm ci
cargo build / tauri build
package artifact
copy output to artifacts/
```

AUR uses the pinned `WEBCLIENTS_COMMIT` rather than only the moving
`WEBCLIENTS_REF`.

## Package Spec Jobs

The `spec` stage generates release metadata that can be used independently of
the built packages:

- `spec:aur-pkgbuild` generates `PKGBUILD`.
- `spec:rpm-spec` generates `proton-drive.spec`.
- `spec:source-dist` creates a source tarball and SHA256 file.

Artifacts from this stage expire after 90 days.

## Release Job

The `release` job runs in the `release` stage using GitLab `release-cli`.

It needs artifacts from the package matrix, including:

- AppImage
- Flatpak GNOME 49/50
- Snap core24/core26
- AUR
- Debian and Ubuntu DEBs
- Fedora, EL10, and openSUSE RPMs
- Alpine APK tarballs

The job uploads package files to the GitLab Generic Package Registry under:

```text
releases/${TAG}/${artifact-name}
```

Then it creates a GitLab release named:

```text
Proton Drive Linux ${TAG}
```

with asset links pointing at those uploaded artifacts.

## Publish Jobs

Publish jobs extend `.rules:publish`, run only for version tags, and are manual
fall-through jobs by design.

Current publish jobs:

- `publish:aur`
  - Updates the AUR repository over SSH.
  - Uses `AUR_SSH_PRIVATE_KEY`.
  - Refreshes source and WebClients checksums.

- `publish:flatpak`
  - Updates the Flathub repository over SSH.
  - Uses `FLATHUB_SSH_PRIVATE_KEY`.
  - Requires the Flathub repository/submission to already exist.

- `publish:snap`
  - Uploads the built Snap through Snapcraft in Docker.
  - Uses `SNAPCRAFT_STORE_CREDENTIALS`.
  - Defaults to `SNAP_BASE=core24` and `SNAP_CHANNEL=stable`.

## VM Smoke Jobs

`.gitlab-ci-vm-tests.yml` adds manual SSH checks for the Unraid-hosted GitLab
runner environment.

Jobs:

- `vm:ssh:smoke`
  - Matrix over `tower`, `debian12`, `debian13`, `alpine320`, and `alpine322`.
  - Verifies runner SSH credentials and basic host access.

- `vm:ssh:diagnostics`
  - Prints SSH version and checks multiple host aliases.
  - Manual and allowed to fail.

These jobs are diagnostic rather than part of the default release gate.

## AI Documentation Audit Pipeline

The documentation audit path is integrated into GitLab stages:

```text
detect -> audit -> update
```

Jobs:

- `docs:detect-changes`
  - Finds changed files by schedule window or commit diff.

- `docs:resolve-mapping`
  - Reads `docs/mapping.yaml`.
  - Writes `docs/affected_docs.json`.

- `docs:audit-gate`
  - Calls the configured LLM provider through `scripts/ci/ai-doc-gate.sh`.
  - Writes `docs/stale_docs.json`.
  - Warns on scheduled runs.
  - Can fail release-gate mode for critical stale docs.

- `docs:auto-update`
  - Runs automatically for scheduled doc audits.
  - Manual for web/API doc audits.
  - Uses `scripts/ci/ai-doc-update.sh`.
  - Opens a documentation MR when changes are produced.

Required variables for full doc-audit operation:

- `RUN_DOC_AUDIT=true`
- `DEEPSEEK_API_KEY` or `OPENAI_API_KEY`
- `DOC_AUDIT_PUSH_TOKEN` if auto-update should push branches and open MRs

## GitHub Actions Mirror

GitHub Actions are defined under `.github/workflows/`.

Primary workflows:

- `package-workflows.yml`
  - Manual `workflow_dispatch` package matrix.
  - Also handles opened issues and `pull_request_target` for maintenance-style
    automation.
  - Uses composite action implementations under `.github/workflows/<target>/`.

- `sync-to-gitlab.yml`
  - Mirrors GitHub issues, PRs, and comments into GitLab issues.
  - Uses `GITLAB_SYNC_TOKEN` and `GITLAB_PROJECT_ID`.

- `sanity.yml`
  - Public sanity checks for the mirror.

Package workflow implementations exist for APK, AppImage, AUR, DEB, Flatpak,
RPM, Snap, package-spec generation, release, PR labeling, issue labeling, and
publishing helpers.

GitHub package workflows are retained for manual checks and maintenance. They
should not become the automatic release path while GitLab remains authoritative.

## Operational Checklist

Before a release tag:

- Confirm package versions agree across `package.json`, `package-lock.json`,
  `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, and
  `src-tauri/tauri.conf.json`.
- Run an explicit GitLab release-test pipeline if needed:
  `RUN_RELEASE_TESTS=true`.
- Confirm required publish secrets exist for any publish jobs that will be run.
- Confirm `docs/release-checklist.md` is current.
- Tag from the authoritative GitLab `main`.

After major CI changes:

- Parse `.gitlab-ci.yml`.
- Run `git diff --check`.
- Update `docs/mapping.yaml` so documentation audit coverage stays aligned.
- Refresh Graphify with `graphify update .` or a full extraction when semantic
  docs change significantly.
