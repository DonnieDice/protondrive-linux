# CI Pipeline Reference — GitLab CI

> Companion document to `.gitlab-ci.yml`. Describes all stages, jobs, rules,
> artifact outputs, and trigger conditions for the Proton Drive Linux desktop
> client's GitLab CI pipeline.

---

## Pipeline Overview

The pipeline runs in **ten sequential stages**:

```
test  →  build  →  gate  →  transfer  →  install  →  vmtest  →  report  →  spec  →  release  →  publish
```

- **test** — pre-build regression checks (login/routing, sync, Rust formatting, Clippy lints, unit tests).
- **build** — compiles the Tauri app and packages it for every supported distribution format.
- **gate** — confirms all distro builds passed before deploying to VMs; transfer/install/vmtest depend on it.
- **transfer** — SCPs the build artifact to each target VM in the LAN test matrix.
- **install** — installs the package on each VM using the distro-specific package manager.
- **vmtest** — runs regression checks and GUI load tests on each VM.
- **report** — aggregates deployment/verification results, generates HTML reports, screenshots gallery, and GitLab Pages.
- **spec** — generates distro-specific package metadata files (PKGBUILD, .spec, source tarball).
- **release** — aggregates all build artifacts and creates a GitLab Release with tagged assets.
- **publish** — pushes artifacts to external distribution channels (AUR, Flathub, Snap Store).

### Workflow Rules

The pipeline is triggered for:

| Event | Runs? |
|---|---|
| Merge request (`merge_request_event`) | Yes — all test, build, gate, transfer, install, vmtest, report & spec jobs |
| Branch push (any branch, no open MR) | Yes — all test, build, gate, transfer, install, vmtest, report & spec jobs |
| Branch push with open MR | **No** — skipped to prevent duplicate pipelines (MR pipeline takes priority) |
| Tag push (`CI_COMMIT_TAG`) | Yes — full pipeline including release & publish |
| Manual trigger | Yes — any jobs with `when: manual` fallthrough |

> **Duplicate pipeline prevention:** When a branch has an open merge request, the
> branch pipeline is automatically skipped (`when: never`). Only the MR pipeline
> runs, avoiding redundant builds.

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

## Stage: `test`

> Pre-build regression checks. All test jobs extend `.rules:test` and share
> `interruptible: true`. They run on every MR, branch push, and tag push.
> Timeout: 10–30 minutes.

### `test:login-routing-regression`

| Image | Timeout | Dependencies |
|---|---|---|
| `alpine:latest` | 10m | None |

Runs `scripts/ci/regression/login-routing.sh` — checks that login/session
routing logic hasn't regressed.

### `test:sync-regression`

| Image | Timeout | Dependencies |
|---|---|---|
| `alpine:latest` | 10m | None |

Runs `scripts/ci/regression/sync.sh` — validates sync functionality against
synthetic state.

### `test:fmt`

| Image | Timeout | Dependencies |
|---|---|---|
| `debian:12` | 10m | None |

Runs `cargo fmt -- --check` on the `src-tauri` crate. Has its own cargo cache
(`test-fmt-cargo`) separate from build caches.

### `test:clippy`

| Image | Timeout | Dependencies |
|---|---|---|
| `debian:12` | 30m | None |

Runs `cargo clippy` with `-W clippy::all -W clippy::pedantic`. Requires the
full GTK/WebKit toolchain for dependency resolution. Stubs `WebClients/`
with a minimal HTML fixture before linting.

### `test:rust`

| Image | Timeout | Dependencies |
|---|---|---|
| `debian:12` | 30m | None |

Runs `cargo test -- --nocapture` on the `src-tauri` crate. Has its own cargo
cache (`test-rust-cargo`) and stubs `WebClients/` with a minimal HTML fixture
before running tests.

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

## Stage: `gate`

> Confirms all distro builds succeeded before any deploy/VM stages run.
> One job only: `build:gate`. Report jobs do **not** depend on this gate
> and always run regardless of its result.

### `build:gate`

| Image | Timeout | Rules |
|---|---|---|
| `alpine:latest` | — | MR, branch push, tag push |

**Dependencies (needs):** All 10 build jobs that feed into the transfer/install/vmtest pipeline
(APK Alpine 3.20 + 3.22, AUR, DEB Debian 12 + 13, DEB Ubuntu 24.04 + 26.04,
RPM EL10 + Fedora 43 + openSUSE Tumbleweed).

**What happens:**

If any upstream build job failed, `build:gate` is skipped, which cascades:
- `transfer/*` (all need `build:gate`) → skipped
- `install/*` (needs transfer) → skipped
- `vmtest/*` (needs install) → skipped
- Report jobs are unaffected and always run.

If all builds passed, the gate prints a confirmation message and the deploy stages proceed.

---

## Stage: `transfer`

> SCPs the build artifact to each target VM. One job per distro.
> All jobs extend `.transfer:base` with shared rules (MR, branch push, tag push, or manual).
> Image: `alpine:latest`. Artifacts include a JSON result record and a dotenv file (`REMOTE_PKG_PATH`)
> consumed by the `install` stage.

### Jobs

| Job | VM |
|---|---|
| `transfer:alpine-3.20` | Alpine 3.20 (192.168.1.x) |
| `transfer:alpine-3.22` | Alpine 3.22 |
| `transfer:debian-12` | Debian 12 |
| `transfer:debian-13` | Debian 13 |
| `transfer:ubuntu-24.04` | Ubuntu 24.04 |
| `transfer:ubuntu-26.04` | Ubuntu 26.04 |
| `transfer:el10` | CentOS Stream 10 (EPEL+CRB enabled) |
| `transfer:fedora-43` | Fedora 43 |
| `transfer:opensuse-tumbleweed` | openSUSE Tumbleweed |
| `transfer:arch` | Arch Linux |

Each job locates the build artifact by distro, SCPs it to the target VM, and emits
`transfer-results/<label>.json` + `transfer-results/<label>.env` dotenv with the
remote package path for the downstream `install` job.

---

## Stage: `install`

> Installs the package on each VM using distro-specific package managers.
> One job per distro. Reads `REMOTE_PKG_PATH` from the transfer stage dotenv artifact.
> Re-exports `transfer-results/` so the report stage can aggregate all three result sets.
> Image: `alpine:latest`. Rules: MR, branch push, tag push, or manual.

### Jobs

| Job | Package Manager |
|---|---|
| `install:alpine-3.20` | `apk` |
| `install:alpine-3.22` | `apk` |
| `install:debian-12` | `apt` |
| `install:debian-13` | `apt` |
| `install:ubuntu-24.04` | `apt` |
| `install:ubuntu-26.04` | `apt` |
| `install:el10` | `dnf` |
| `install:fedora-43` | `dnf` |
| `install:opensuse-tumbleweed` | `zypper` |
| `install:arch` | `pacman` |

Install scripts live under `scripts/ci/install/<distro>/install.sh`. Each is a
minimal distro-specific script — dependency resolution is delegated to the
package manager. After install, the job writes `install-results/<label>.json`.

---

## Stage: `vmtest`

> Runs regression checks and GUI load tests on each VM after the install stage.
> One job per distro. Re-exports all three result directories (`transfer-results/`,
> `install-results/`, `test-results/`) so the `report` stage only depends on vmtest
> jobs to get the full picture.
>
> Image: `alpine:latest`. Rules: MR, branch push, tag push, or manual.
> Artifacts expire in **30 days** and also include compositor test screenshots
> (`verify-results/ui-screenshots/`) for OCR debugging.

### Jobs

| Job | VM |
|---|---|
| `vmtest:alpine-3.20` | Alpine 3.20 |
| `vmtest:alpine-3.22` | Alpine 3.22 |
| `vmtest:debian-12` | Debian 12 |
| `vmtest:debian-13` | Debian 13 |
| `vmtest:ubuntu-24.04` | Ubuntu 24.04 |
| `vmtest:ubuntu-26.04` | Ubuntu 26.04 |
| `vmtest:rpm-el10` | CentOS Stream 10 |
| `vmtest:rpm-fedora-43` | Fedora 43 |
| `vmtest:rpm-opensuse-tumbleweed` | openSUSE Tumbleweed |
| `vmtest:aur` | Arch Linux |

Test scripts live under `scripts/ci/vmtest/<distro>/test.sh` and run both
regression checks (handled by `scripts/ci/lib/_test_common.sh`) and a GUI load
test via `xdotool` + screenshot OCR.

---

## Stage: `report`

> The report stage aggregates results from all upstream VM stages and generates
> browsable artifacts. It has **five jobs**: the deployment matrix (JUnit for MR
> Tests tab), Robot Framework HTML, pytest HTML, a UI screenshots gallery, and
> GitLab Pages aggregating everything into a single browsable site.
>
> All report jobs use `when: always` so reports exist even when upstream stages fail.
> Artifacts expire in **90 days** (except Pages at 30 days).

### `report:deployment-matrix`

| Image | Dependencies |
|---|---|
| `python:3.12-slim` | All 10 vmtest jobs (artifacts: true) |

**What it does:**

1. Collects `transfer-results/`, `install-results/`, `test-results/` from all
   vmtest job artifacts.
2. Runs `scripts/ci/lib/verify-matrix.py` to produce:
   - `reports/deployment-matrix.md` — Markdown table showing per-distro transfer/install/test status
   - `reports/deployment-matrix.json` — structured JSON for downstream tooling
   - `reports/deployment-matrix.junit.xml` — JUnit XML report surfaced in the GitLab MR Tests tab

**Output artifacts:**

| Artifact | Always? |
|---|---|
| `reports/deployment-matrix.md` | Yes (`when: always`) |
| `reports/deployment-matrix.json` | Yes (`when: always`) |
| `reports/deployment-matrix.junit.xml` | Yes (via `reports: junit`) |

### `report:robot-html`

| Image | Dependencies |
|---|---|
| `python:3.12-slim` | `vmtest:debian-12` (artifacts: true) |

Generates a Robot Framework HTML report from test results using
`scripts/ci/lib/generate-robot-report.py`. Output lands in `reports/robot/` and
is browsable via the GitLab artifact browser (`CI/CD → Jobs → Browse`).

### `report:pytest-html`

| Image | Dependencies |
|---|---|
| `python:3.12-slim` | None |

Runs `pytest` on `tests/unit/` with `--html` and `--junit-xml` reporters.
Uses `|| true` so test failures in unit tests don't block the report.
Output lands in `reports/pytest/` (both HTML and JUnit XML).

### `report:ui-screenshots`

| Image | Dependencies |
|---|---|
| `python:3.12-slim` | `vmtest:debian-12`, `vmtest:ubuntu-24.04` (artifacts: true) |

Generates a browsable screenshot gallery using
`scripts/ci/lib/generate-screenshot-gallery.py`. Reads compositor test
screenshots from `verify-results/ui-screenshots/` and writes an `index.html`
gallery to `reports/screenshots/`.

### `pages` — GitLab Pages

| Image | Dependencies |
|---|---|
| `python:3.12-slim` | `report:deployment-matrix`, `report:robot-html`, `report:pytest-html`, `report:ui-screenshots` (all artifacts: true) |

> The job name `pages` is special in GitLab — GitLab recognises it and serves the
> `public/` directory as a static site.

**Rules:** Only runs on `main` branch pushes or tag pushes (not on every branch
or MR).

**What it does:**

1. Copies all report artifacts into `public/` under subdirectories (`robot/`,
   `pytest/`, `screenshots/`).
2. Generates a landing page index from the deployment matrix JSON.
3. Publishes to **GitLab Pages** at:
   `http://pages.dicematrix.cloud/donniedice/protondrive-linux`

**Infrastructure requirements:**
- Wildcard DNS `*.pages.dicematrix.cloud` → `192.168.1.31`
- `gitlab.rb` config: `pages_external_url` set, `gitlab_pages['enable'] = true`

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
| **Merge request** | All test jobs + all build jobs + all gate jobs + all transfer jobs + all install jobs + all vmtest jobs + report + all spec jobs |
| **Branch push** (no open MR) | All test jobs + all build jobs + all gate jobs + all transfer jobs + all install jobs + all vmtest jobs + report + all spec jobs |
| **Branch push** (open MR exists) | **Skipped entirely** — MR pipeline takes priority |
| **Tag push (`v*`)** | All test jobs + all build jobs + all gate jobs + all transfer jobs + all install jobs + all vmtest jobs + report + all spec jobs + release + publish:aur + publish:flatpak + publish:snap |
| **Main branch push** | All test jobs + all build jobs + all gate jobs + all transfer jobs + all install jobs + all vmtest jobs + report + all spec jobs + **release** (creates GitLab Release) |
| **Manual trigger** | Any job with `when: manual` fallthrough |
