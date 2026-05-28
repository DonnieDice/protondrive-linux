# CI Authority & Mirroring

This document defines the authority model and mirroring rules between the
two CI systems that serve protondrive-linux: **GitLab CI** (authoritative)
and **GitHub Actions** (mirror).

## Authority: GitLab CI is the source of truth

**GitLab CI** (`/.gitlab-ci.yml`) hosts the authoritative pipeline at
`gitlab.dicematrix.cloud`. All builds, specs, releases, and publishes
originate here. GitHub Actions mirrors the build matrix so that GitHub-based
contributors get CI feedback without leaving the platform, but GitLab CI
output is the official release artifact.

## Pipeline stages (GitLab CI)

The GitLab pipeline runs four ordered stages:

| Stage    | Purpose                                                                    |
|----------|----------------------------------------------------------------------------|
| `build`  | Cross-distro binary + package compilation (all targets)                    |
| `spec`   | Generate PKGBUILD, RPM specfile, and source distribution archives           |
| `release`| Create a GitLab release with all artifacts uploaded to the Package Registry |
| `publish`| Push packages to external distribution channels (AUR, Flathub, Snap Store)  |

### Build matrix

Each build job runs in a distro-specific container or image. All jobs use
the `.rules:build` rule template (runs on MR, branch push, or tag push;
manual with `allow_failure: true` otherwise).

| Build job                          | Container/Image                         | Output format      |
|------------------------------------|------------------------------------------|--------------------|
| `build:apk:alpine-3.20`            | `alpine:3.20`                           | `.apk.tar.gz`      |
| `build:apk:alpine-3.22`            | `alpine:3.22`                           | `.apk.tar.gz`      |
| `build:apk:alpine-3.23`            | `alpine:3.23`                           | `.apk.tar.gz`      |
| `build:appimage`                   | `debian:12`                             | `.AppImage`        |
| `build:aur`                        | `archlinux:base-devel`                  | `.pkg.tar.zst`     |
| `build:deb:debian-12`              | `debian:12`                             | `.deb`             |
| `build:deb:debian-13`              | `debian:13`                             | `.deb`             |
| `build:deb:ubuntu-24.04`           | `ubuntu:24.04`                          | `.deb`             |
| `build:deb:ubuntu-26.04`           | `ubuntu:26.04`                          | `.deb`             |
| `build:flatpak:gnome-49`           | `ubuntu:24.04` (extra flatpak layers)   | `.flatpak`         |
| `build:flatpak:gnome-50`           | `ubuntu:24.04` (extra flatpak layers)   | `.flatpak`         |
| `build:rpm:el10`                   | `quay.io/centos/centos:stream10`        | `.rpm`             |
| `build:rpm:fedora-43`              | `fedora:43`                             | `.rpm`             |
| `build:rpm:fedora-44`              | `fedora:44`                             | `.rpm`             |
| `build:rpm:opensuse-tumbleweed`    | `opensuse/tumbleweed:latest`            | `.rpm`             |
| `build:snap:core24`                | `ubuntu:24.04` + `docker:dind`          | `.snap`            |
| `build:snap:core26`                | `ubuntu:24.04` + `docker:dind`          | `.snap`            |

### Spec stage

| Job               | Output                          |
|-------------------|---------------------------------|
| `spec:aur-pkgbuild`   | `PKGBUILD` for AUR           |
| `spec:rpm-spec`       | `proton-drive.spec` for RPM  |
| `spec:source-dist`    | Source tarball + SHA256      |

All spec jobs use `.rules:build` (run on every MR/branch/tag push).

### Release stage

`release` runs only on:
- Push to `main`
- Tags matching `^v.*`

It collects artifacts from every build job via `needs`, uploads them to the
GitLab Generic Package Registry, and creates a GitLab release with asset
links.

### Publish stage

Publish is **manual** for tag pushes only (`.rules:publish`):

| Job                | Target channel                    | Mechanism                |
|--------------------|-----------------------------------|--------------------------|
| `publish:aur`      | AUR (`aur.archlinux.org`)         | SSH key push to AUR git  |
| `publish:flatpak`  | Flathub (`github.com/flathub`)    | SSH key push to flathub  |
| `publish:snap`     | Snap Store                        | `snapcraft upload`       |

### Workflow rules

```yaml
- Merge requests: run all matching jobs
- Branch pushes:  run all matching jobs
- Tag pushes:     run all matching jobs + release + (manual) publish
- Otherwise:      manual, allow_failure: true
```

## Mirroring: GitHub Actions

GitHub Actions (`/.github/workflows/package-workflows.yml`) mirrors the
GitLab build matrix so that contributors opening PRs or pushing branches on
GitHub receive CI feedback automatically.

### Mirrored build targets

Each build target has its own composite action under
`.github/workflows/<type>/<variant>/action.yml`. The top-level workflow
(`package-workflows.yml`) invokes them with the same distro-specific
settings (containers, env vars, patches) as the GitLab CI.

| GitHub job                        | Mirrors GitLab job                  |
|-----------------------------------|-------------------------------------|
| `build_apk_alpine_3_20`           | `build:apk:alpine-3.20`            |
| `build_apk_alpine_3_22`           | `build:apk:alpine-3.22`            |
| `build_apk_alpine_3_23`           | `build:apk:alpine-3.23`            |
| `build_appimage`                  | `build:appimage`                   |
| `build_aur`                       | `build:aur`                        |
| `build_deb_debian_12`             | `build:deb:debian-12`              |
| `build_deb_debian_13`             | `build:deb:debian-13`              |
| `build_deb_ubuntu_24_04`          | `build:deb:ubuntu-24.04`           |
| `build_deb_ubuntu_26_04`          | `build:deb:ubuntu-26.04`           |
| `build_flatpak_gnome_49`          | `build:flatpak:gnome-49`           |
| `build_flatpak_gnome_50`          | `build:flatpak:gnome-50`           |
| `build_rpm_el10`                  | `build:rpm:el10`                   |
| `build_rpm_fedora_43`             | `build:rpm:fedora-43`              |
| `build_rpm_fedora_44`             | `build:rpm:fedora-44`              |
| `build_rpm_opensuse_tumbleweed`   | `build:rpm:opensuse-tumbleweed`    |
| `build_snap_core24`               | `build:snap:core24`                |
| `build_snap_core26`               | `build:snap:core26`                |

### Not mirrored

The following GitLab CI stages are **not** replicated in GitHub Actions:

- **spec** — package spec generation (PKGBUILD, RPM spec, source tarball)
  is exclusive to GitLab CI. GitHub does not run `spec:aur-pkgbuild`,
  `spec:rpm-spec`, or `spec:source-dist`.
- **release** — GitLab releases with the Package Registry asset links are
  not mirrored. GitHub has its own `release` event type that triggers the
  publish sub-actions.
- **publish** — While GitHub has publish actions for AUR, Flatpak, and Snap
  under `.github/workflows/`, these are triggered by `release` events and
  `workflow_dispatch`, not by the mirror pipeline itself. They are separate
  from the GitLab publish stage.

### Exclusive to GitHub Actions

GitHub Actions runs additional workflows that have no GitLab counterpart:

| Workflow                            | Purpose                                    |
|-------------------------------------|--------------------------------------------|
| `sync-to-gitlab.yml`                | Mirror issues, PRs, and comments to GitLab |
| `issue-auto-label`                  | Auto-label issues based on content         |
| `pr-auto-label`                     | Auto-label PRs based on content            |
| `release` (maintenance)             | Compose release metadata                   |

### GitHub workflow triggers

The GitHub workflow triggers on:
- `push` to `main`, `alpha`, `feature/**`, `fix/**`, `chore/**`, and `v*` tags
- `pull_request` to `main`
- `pull_request_target` (opened)
- `issues` (opened)
- `release` (published)
- `workflow_dispatch` (manual with input parameters)

## Issue and PR mirroring: GitHub → GitLab

The `sync-to-gitlab.yml` workflow mirrors GitHub issues, pull requests, and
comments to GitLab using the GitLab REST API. This ensures that
GitLab-side contributors and CI runners see the full discussion history.

- **Issues**: Created/updated in GitLab with `[GH#N]` prefix. State changes
  (close/reopen) are mirrored.
- **Pull requests**: Synced as GitLab issues with `[GH-PR#N]` prefix and a
  `github-pr` label.
- **Comments**: Posted as GitLab notes on the corresponding mirrored issue.
  Deletions are skipped.
- **Credentials**: Uses `GITLAB_SYNC_TOKEN` secret and targets
  `gitlab.dicematrix.cloud`.

## Sync direction is GitHub → GitLab only

There is **no automated sync in the reverse direction** (GitLab → GitHub).
GitHub is the primary collaboration surface for issues, PRs, and community
contributions. GitLab CI is the authoritative pipeline runner. The
sync-to-gitlab workflow ensures GitLab is aware of GitHub activity, but
GitLab-tracked issues or MRs must be manually cross-posted to GitHub if
they need visibility there.

## Adding a new build target

When adding a new distro/package build target:

1. **GitLab CI first** — add the job to `/.gitlab-ci.yml` using the
   appropriate `.rules:build` template, distro-specific container image, and
   version/patch extraction logic. See `docs/new-build-checklist.md` for the
   detailed procedure.
2. **GitHub mirror** — create a composite action at
   `.github/workflows/<type>/<variant>/action.yml` and register it in
   `package-workflows.yml`.
3. **Release stage** — add the new build job to `release`'s `needs` list in
   `.gitlab-ci.yml` if it should be included in releases.
4. **Publish (if applicable)** — add a `publish:` job to `.gitlab-ci.yml`
   and an optional publish action under `.github/workflows/`.

## Security notes

- Snap builds require `docker:dind` (Docker-in-Docker). The GitLab runner
  must have `privileged = true` in its config.
- Publish jobs use SSH private keys stored as CI/CD variables
  (`AUR_SSH_PRIVATE_KEY`, `FLATHUB_SSH_PRIVATE_KEY`) and Snapcraft
  credentials (`SNAPCRAFT_STORE_CREDENTIALS`).
- The `sync-to-gitlab.yml` workflow uses `GITLAB_SYNC_TOKEN` — a GitLab
  personal access token stored as a GitHub secret.
- All artifacts expire after 30 days (90 days for spec artifacts).

## CI scripts in `scripts/ci/`

The `scripts/ci/` directory holds standalone build scripts that are invoked by
GitLab CI (and, where applicable, by GitHub Actions). Each script produces a
specific package format for a specific distro. Most build jobs execute their
logic inline inside the CI YAML; only the following targets have extracted
scripts:

| Script | Purpose | GitLab CI job (stage) |
|--------|---------|-----------------------|
| `scripts/ci/build-alpine-320-apk.sh` | Build a portable APK (`.apk.tar.gz`) for Alpine Linux 3.20 (musl). Creates a clean git worktree, applies the Alpine 3.20 patch, builds the Tauri binary via `npx tauri build`, strips debug symbols, and packs into a redistributable archive. | `build:apk:alpine-3.20` — stage: `build` |
| `scripts/ci/build-alpine-322-apk.sh` | Build an APK (`.apk.tar.gz`) for Alpine Linux 3.22 (musl). Same flow as the 3.20 script but applies the Alpine 3.22 patch. | `build:apk:alpine-3.22` — stage: `build` |
| `scripts/ci/build-alpine-323-apk.sh` | Build an APK (`.apk.tar.gz`) for Alpine Linux 3.23 (musl). Same flow as the 3.20/3.22 scripts but applies the Alpine 3.23 patch. | `build:apk:alpine-3.23` — stage: `build` |
| `scripts/ci/build-aur-package.sh` | Build an Arch Linux AUR package (`.pkg.tar.zst`) from a pre-compiled binary. Generates a PKGBUILD, bundles the binary, desktop entry, and icons, then runs `makepkg` as an unprivileged `builder` user. Accepts positional args for target, version, binary path, icons directory, and repo root. | `build:aur` — stage: `build` |
| `scripts/ci/build-opensuse-tumbleweed-rpm.sh` | Build an RPM package for openSUSE Tumbleweed. Applies the `opensuse.tumbleweed` patch, sets up WebKitGTK overlay support, runs `tauri build --bundles rpm`, normalises the RPM filename, and copies the artifact to the output directory. | `build:rpm:opensuse-tumbleweed` — stage: `build` |

All scripts reside in the `build` stage. The remaining build targets (Debian,
Ubuntu, Fedora, EL10, Flatpak, Snap, AppImage) have their build logic defined
inline in `.gitlab-ci.yml` or in GitHub composite actions and do not have
a dedicated script under `scripts/ci/`.

## Quick reference: where to go for what

| Need                                 | System          | File                                          |
|--------------------------------------|-----------------|-----------------------------------------------|
| Review build pipeline definition     | GitLab CI       | `/.gitlab-ci.yml`                             |
| Review GitHub mirror of build matrix | GitHub Actions  | `/.github/workflows/package-workflows.yml`    |
| Inspect a specific build action      | GitHub Actions  | `/.github/workflows/<type>/<variant>/action.yml` |
| View issue/PR sync rules             | GitHub Actions  | `/.github/workflows/sync-to-gitlab.yml`       |
| Add a new build target               | Both            | `docs/new-build-checklist.md`                 |
| Understand packaging conventions     | Docs            | `docs/packaging.md`                           |
| Inspect CI build scripts             | GitLab CI       | `scripts/ci/*.sh`                             |
