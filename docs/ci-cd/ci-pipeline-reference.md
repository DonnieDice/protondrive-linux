# CI Pipeline Reference — GitLab CI

> Companion document to `.gitlab-ci.yml`. Describes all stages, jobs, rules,
> artifact outputs, and trigger conditions for the Proton Drive Linux desktop
> client's GitLab CI pipeline.

---

## Pipeline Overview

The pipeline runs in **four sequential stages**:

```
build  →  spec  →  release  →  publish
```

- **build** — compiles the Tauri app and packages it for every supported distribution format.
- **spec** — generates distro-specific package metadata files (PKGBUILD, .spec, source tarball).
- **release** — aggregates all build artifacts and creates a GitLab Release with tagged assets.
- **publish** — pushes artifacts to external distribution channels (AUR, Flathub, Snap Store).

### Workflow Rules

The pipeline is triggered for:

| Event | Runs? |
|---|---|
| Merge request (`merge_request_event`) | Yes — all build & spec jobs |
| Branch push (any branch) | Yes — all build & spec jobs |
| Tag push (`CI_COMMIT_TAG`) | Yes — full pipeline including release & publish |
| Manual trigger | Yes — build & spec jobs, publish jobs |

---

## Variables

All shared variables are defined in `.gitlab/workflows/_shared.yml` and sourced into
the pipeline via the `include:` directive at the top of `.gitlab-ci.yml`.

| Variable | Value | Purpose |
|---|---|---|
| `RUST_VERSION` | `stable` | Rust toolchain version used across all jobs |
| `WEBCLIENTS_REF` | `main` | Git branch/tag for the WebClients submodule |
| `WEBCLIENTS_COMMIT` | `bbad1a0a482227b93a2e963a232463aede9b8abf` | Pinned commit for AUR builds (fetch by commit, not branch) |
| `CARGO_HOME` | `${CI_PROJECT_DIR}/.cargo` | Local cargo cache path |
| `DOCKER_HOST` | `tcp://docker:2375` | Docker daemon endpoint (for DinD services) |
| `DOCKER_TLS_CERTDIR` | `""` | Disables TLS for DinD |
| `CARGO_BUILD_JOBS` | `"4"` | Caps `cargo` parallelism so concurrent builds don't oversubscribe the runner's 12-core CPU set — 3 concurrent jobs x 4 parallel compiler threads = 12 threads, a clean 1:1 ratio with no thrash |

---

## Rule Templates (YAML Anchors)

All rule templates below are defined in `.gitlab/workflows/_shared.yml` and shared
across all workflow files via `include:`.

### `.rules:build`
Applied to all **build** and **spec** jobs.
- Runs automatically on: merge request, branch push, tag push.
- Falls through to `when: manual, allow_failure: true` as last resort.

### `.rules:release`
Applied to the **release** job.
- Runs only when: `CI_COMMIT_BRANCH == "main" && push`, **or** tag matching `/^v.*/`.
- Otherwise: `when: never`.

### `.rules:publish`
Applied to all **publish** jobs.
- Runs only when tag matches `/^v.*/`.
- Falls through to `when: manual, allow_failure: true`.

---

## Reusable Script Fragments

The following YAML anchors are defined in `.gitlab/workflows/_shared.yml`.

### `.install_rust`
A `before_script` block reused by every build job. Installs the Rust toolchain via rustup if
`$CARGO_HOME/bin/rustup` doesn't already exist, then prints `rustc --version` and
`cargo --version`.

### `.install_rust_full`
Like `.install_rust` but also installs full GTK/WebKit development dependencies
(`libwebkit2gtk-4.1-dev`, `libgtk-3-dev`, `libayatana-appindicator3-dev`,
`librsvg2-dev`, `libsoup-3.0-dev`, etc.) required by Tauri builds.

---

## Stage: `build`

> All build jobs share the pattern: install system deps → install Rust → clone
> WebClients → apply distro patch → build web clients → sync version → npm install
> → cargo build → extract binary → package → drop into `artifacts/`.
>
> Artifacts expire in **30 days** and all outputs land in `artifacts/`.

### APK (Alpine Linux)

| Job | Image | Patch | Suffix | Artifact Pattern |
|---|---|---|---|---|
| `build:apk:alpine-3.20` | `alpine:3.20` | `alpine.3.20` | `alpine320` | `proton-drive_*_alpine320_amd64.apk.tar.gz` |
| `build:apk:alpine-3.22` | `alpine:3.22` | `alpine.3.22` | `alpine322` | `proton-drive_*_alpine322_amd64.apk.tar.gz` |
| `build:apk:alpine-3.23` | `alpine:3.23` | `alpine.3.23` | `alpine323` | `proton-drive_*_alpine323_amd64.apk.tar.gz` |

Uses `x86_64-unknown-linux-musl` target with `-C target-feature=-crt-static`.
Patches applied `--reverse --check` first (idempotent apply).
Output is a `.tar.gz` containing the FHS layout: binary, `.desktop` file, icons.

### AppImage

| Job | Image | Patch | Suffix | Artifact Pattern |
|---|---|---|---|---|
| `build:appimage` | `debian:12` | `linux-baseline` | `linux-baseline` | `proton-drive_*_linux-baseline_amd64.AppImage` |

Builds with `cargo build --release` (not Tauri CLI). Creates an AppDir with
entry point and all icons, then packages with `appimagetool`.
AppRun wrapper sets `WEBKIT_DISABLE_DMABUF_RENDERER`, `WEBKIT_DISABLE_COMPOSITING_MODE`,
`WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS`, `GDK_GL=software`, `GSK_RENDERER=cairo`.

### AUR (Arch Linux)

| Job | Image | Patch | Artifact Pattern |
|---|---|---|---|
| `build:aur` | `archlinux:base-devel` | `arch-native` | `*.pkg.tar.zst` + `.SRCINFO` |

WebClients is fetched by **pinned commit** (`WEBCLIENTS_COMMIT`) rather than branch.
Uses `scripts/ci/build-aur-package.sh` to produce the Arch package, then generates
a `PKGBUILD` and `.SRCINFO` for the AUR repository.

### DEB (Debian / Ubuntu)

| Job | Image | Patch | Suffix | Artifact Pattern |
|---|---|---|---|---|
| `build:deb:debian-12` | `debian:12` | `debian.12` | `debian12` | `proton-drive_*_debian12_amd64.deb` |
| `build:deb:debian-13` | `debian:13` | `debian.13` | `debian13` | `proton-drive_*_debian13_amd64.deb` |
| `build:deb:ubuntu-24.04` | `ubuntu:24.04` | `ubuntu.24.04` | `ubuntu24.04` | `proton-drive_*_ubuntu24.04_amd64.deb` |
| `build:deb:ubuntu-26.04` | `ubuntu:26.04` | `ubuntu.26.04` | `ubuntu26.04` | `proton-drive_*_ubuntu26.04_amd64.deb` |

Ubuntu jobs set `DEBIAN_FRONTEND: noninteractive`.
Uses `npx tauri build --bundles deb` for packaging. The resulting `.deb` file is
renamed with the distro suffix.

### Flatpak

| Job | Image | Patch | GNOME Runtime | Artifact Pattern |
|---|---|---|---|---|
| `build:flatpak:gnome-49` | `ubuntu:24.04` | `org.gnome.Platform.49` | 49 | `proton-drive_*_gnome49.flatpak` |
| `build:flatpak:gnome-50` | `ubuntu:24.04` | `org.gnome.Platform.50` | 50 | `proton-drive_*_gnome50.flatpak` |

Requires `--disable-rofiles-fuse` in flatpak-builder (or privileged runner mode).
Installs GNOME Platform/SDK from Flathub. Builds the binary with plain `cargo
build --release`, then uses `flatpak-builder` + `flatpak build-bundle`.
Flatpak sandbox permits: network, IPC, X11, Wayland, PulseAudio, DRI, downloads
directory, documents directory, secrets D-Bus, and notifications D-Bus.

### RPM (CentOS / Fedora / openSUSE)

| Job | Image | Patch | Artifact Pattern |
|---|---|---|---|
| `build:rpm:el10` | `quay.io/centos/centos:stream10` | `el10` | `proton-drive-*.rpm` |
| `build:rpm:fedora-43` | `fedora:43` | `fedora.43` | `proton-drive-*.rpm` |
| `build:rpm:fedora-44` | `fedora:44` | `fedora.44` | `proton-drive-*.rpm` |
| `build:rpm:opensuse-tumbleweed` | `opensuse/tumbleweed:latest` | `opensuse.tumbleweed` | `proton-drive-*.rpm` |

CentOS Stream 10 enables CRB + EPEL repos for dependencies.
openSUSE has retry logic for `zypper refresh` (5 attempts) and `zypper install`
(3 attempts). All RPM jobs use `npx tauri build --bundles rpm` and rename
`Proton Drive*.rpm` → `proton-drive*.rpm`.
EL10 and openSUSE patches applied `--reverse --check` first (idempotent).

### Snap

| Job | Image | Patch | Artifact Pattern | Notes |
|---|---|---|---|---|
| `build:snap:core24` | `ubuntu:24.04` | `core24` | `proton-drive_*_core24_amd64.snap` | Standard build |
| `build:snap:core26` | `ubuntu:24.04` | `core26` | `proton-drive_*_core26_amd64.snap` | `allow_failure: true` |

Both require **Docker-in-Docker** service (`docker:dind`) and a runner with
`privileged = true`. The binary is built natively, then Snapcraft runs inside a
Docker container (`ghcr.io/canonical/snapcraft:8_core24`) for the final `.snap`
packaging step.
Core26 also patches snapcraft.yaml to `base: core26`, `grade: devel`,
`build-base: devel`.

---

## Stage: `spec`

> These jobs generate package metadata for downstream consumption. They share
> `.rules:build` so they run on every MR/branch/tag. Artifacts expire in **90 days**.

| Job | Image | Output | Description |
|---|---|---|---|
| `spec:aur-pkgbuild` | `node:22` | `PKGBUILD` | Generates AUR PKGBUILD with tag or package.json version, pinned to project URL |
| `spec:rpm-spec` | `node:22` | `proton-drive.spec` | Generates RPM .spec file with BuildRequires/Requires matching the Tauri stack |
| `spec:source-dist` | `alpine/git:latest` | `proton-drive-*.tar.gz` + `.sha256` | Creates a source tarball from `git archive` HEAD with SHA-256 checksum |

---

## Stage: `release`

### `release`

| Extends | Stage | Image | Timeout | Rules |
|---|---|---|---|---|
| `.rules:release` | `release` | `registry.gitlab.com/gitlab-org/release-cli:latest` | — | main branch push OR v* tag |

**Triggers:** Pushes to `main` branch **or** tags matching `/^v.*/`.

**Dependencies (needs):** All 17 build jobs. Each dependency requires `artifacts: true`.
`build:snap:core26` is marked `optional: true` so it won't block release if it failed.

**What it does:**

1. Determines the release tag (pipeline tag, or `v$(package.json version)`).
2. Iterates over all files in `artifacts/` matching: `.AppImage`, `.deb`, `.rpm`,
   `.flatpak`, `.snap`, `.pkg.tar.zst`, `.apk.tar.gz`.
3. Uploads each file to GitLab Generic Packages:
   `https://<gitlab>/api/v4/projects/<id>/packages/generic/releases/<tag>/<filename>`
4. Creates a GitLab Release via `release-cli create` with:
   - Name: `Proton Drive Linux <tag>`
   - Tag: `<tag>`
   - Assets linked to the generic package URLs.

---

## Stage: `publish`

> Runs only on v* tags (`.rules:publish`) or manually. All publish jobs have
> a **15–30 minute timeout**.

### `publish:aur`

| Image | Timeout | Dependencies |
|---|---|---|
| `archlinux:base-devel` | 15m | None (reads artifacts from build:aur) |

**What it does:**

1. Computes SHA-256 for the source tarball and the WebClients archive.
2. Updates `PKGBUILD` with the new version, pkgrel, and WebClients commit hash.
3. Generates a fresh `.SRCINFO`.
4. Clones `ssh://aur@aur.archlinux.org/proton-drive.git`, copies in `PKGBUILD`,
   `.SRCINFO`, and `proton-drive.install`.
5. Commits and force-pushes to AUR.

**Secrets:** `AUR_SSH_PRIVATE_KEY` (SSH key for aur.archlinux.org).

### `publish:flatpak`

| Image | Timeout | Dependencies |
|---|---|---|
| `ubuntu:24.04` | 30m | None |

**What it does:**

1. Computes source checksums for the tag and latest WebClients main commit.
2. Clones `git@github.com:flathub/com.proton.drive.git`.
3. Writes a new `com.proton.drive.yml` that builds from source (git tag + WebClients
   archive) using GNOME Platform SDK extensions (node22, rust-stable).
4. Updates `com.proton.drive.metainfo.xml` with the new release entry.
5. Commits and pushes to Flathub GitHub repo.

**Secrets:** `FLATHUB_SSH_PRIVATE_KEY` (SSH key for github.com/flathub).

### `publish:snap`

| Image | Timeout | Dependencies |
|---|---|---|
| `ubuntu:24.04` | 30m | `build:snap:core24` (artifacts: true) |

Requires Docker-in-Docker service.

**What it does:**

1. Finds the Core24 `.snap` file from build artifacts.
2. Registers the snap name (`snapcraft register --yes proton-drive`) if not yet
   registered (idempotent with `|| true`).
3. Uploads to the Snap Store with `snapcraft upload` on the configured channel
   (default: `stable`), with up to 3 retries (30s delay).

**Secrets:** `SNAPCRAFT_STORE_CREDENTIALS` (Store login token).

---

## Package Matrix (Summary)

| Format | Distros / Variants |
|---|---|
| **APK** | Alpine 3.20, 3.22, 3.23 |
| **AppImage** | Linux baseline (portable) |
| **AUR** | Arch Linux (all rolling) |
| **DEB** | Debian 12, Debian 13, Ubuntu 24.04, Ubuntu 26.04 |
| **Flatpak** | GNOME 49, GNOME 50 |
| **RPM** | CentOS Stream 10, Fedora 43, Fedora 44, openSUSE Tumbleweed |
| **Snap** | Core 24, Core 26 (allow_failure) |

---

## Quick Reference: Which Jobs Run When

| Condition | Jobs |
|---|---|
| **Merge request** | All build jobs + all spec jobs |
| **Branch push** | All build jobs + all spec jobs |
| **Tag push (`v*`)** | All build jobs + all spec jobs + release + publish:aur + publish:flatpak + publish:snap |
| **Main branch push** | All build jobs + all spec jobs + **release** (creates GitLab Release) |
| **Manual trigger** | Any build/spec/publish job |
