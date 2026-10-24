---
title: "CI/CD Pipeline"
created: 2026-05-28
updated: 2026-05-28
type: guide
tags: [ci, build, packaging, release]
sources:
  - .gitlab-ci.yml
---


# CI/CD Pipeline — proton-drive-linux

> Canonical documentation for the CI/CD pipeline architecture.
> Supersedes `ci-authority-and-mirroring.md` and `ci-cd-roadmap.md` as the
> single source of truth for pipeline structure, triggers, and conventions.

## Overview

The project runs **two CI systems** in parallel:

| System | Entrypoint | Role |
|--------|-----------|------|
| **GitLab CI** | `.gitlab-ci.yml` plus the includes `.gitlab-ci-vm-tests.yml`, `.gitlab-ci-vm-harness-15.yml` and `.gitlab/workflows/tests.yml` | **Authoritative** — fast gates, protected package builds, VM smoke tests, spec, release, and publish originate here |
| **GitHub Actions** | `.github/workflows/package-workflows.yml` (588 lines) | **Mirror** — same build matrix on GitHub, triggerable via `workflow_dispatch` only |

**GitLab CI is the source of truth** for all builds, releases, and publishes.
GitHub Actions mirrors the build matrix so that GitHub-based contributors get CI
feedback without leaving the platform, but only GitLab CI output is the official
release artifact.

There is **no automated sync in the reverse direction** (GitLab → GitHub). GitHub
is the primary collaboration surface for issues/PRs; the `sync-to-gitlab.yml`
workflow pushes GitHub activity to GitLab, but GitLab-tracked items must be
manually cross-posted to GitHub.

```mermaid
flowchart TD
    subgraph Triggers
        PUSH["Push (branch)"]
        TAG["Push (v* tag)"]
        PR["MR"]
    end

    subgraph GitLab_CI["GitLab CI (authoritative)"]
        direction LR
        GL_TEST["lint / test / security\nfmt, clippy, unit, regressions"]
        GL_WC["build:webclients\nfrontend built once"]
        GL_BUILD["build:* package jobs\n17 distro containers"]
        GL_SPEC["spec / sign"]
        GL_SMOKE["smoke\nvm:install + vm:regression\non real distro VMs"]
        GL_REL["release"]
        GL_PUB["publish"]
        GL_MIRROR["mirror:github\nallowlisted tree"]
    end

    subgraph GitHub["GitHub (public release mirror)"]
        GH_PUBLIC["Published source + releases"]
        GH_MISC["sanity / sync-to-gitlab\n(trusted authors only)"]
    end

    PUSH --> GL_TEST
    PR --> GL_TEST
    TAG --> GL_TEST
    GL_TEST --> GL_WC --> GL_BUILD
    GL_BUILD --> GL_SPEC --> GL_SMOKE --> GL_REL --> GL_PUB --> GL_MIRROR --> GH_PUBLIC
```

## Pipeline Stages

GitLab CI uses sequential stages. The fast `test` stage always runs on MRs,
branches, and tags. `build:webclients` builds the frontend once for the whole
pipeline; the package jobs that follow reuse it. Package builds run
automatically on tags and `main` and are manual on other refs.

```
detect → audit → update → lint → test → security → build → spec → sign → smoke → release → publish → mirror
```

The VM install and regression jobs (`vm:install:*`, `vm:regression:*`) live in
the `smoke` stage. If a package build fails, its install job has no artifact and
does not run.

### Test — fast gates plus protected regressions (GitLab CI only)

Fast checks run on every MR, branch push, and tag through `.rules:test`:

| Job | Container | Timeout | Purpose |
|-----|-----------|---------|---------|
| `test:fmt` | `debian:12` | 10m | `cargo fmt --check` |
| `test:clippy` | `debian:12` | 30m | `cargo clippy` lint checks |
| `test:rust` | `debian:12` | 30m | `cargo test` — unit tests for login routing, webview cookies, and live sync |
| `test:coverage` | `debian:12` | 45m | `cargo llvm-cov` with Cobertura coverage report; `RUST_COVERAGE_MIN` can be set in GitLab CI variables to ratchet the required line-coverage floor after a measured baseline |

Regression checks are intentionally heavier and run through `.rules:regression`:
protected refs, tags, schedules, or explicit web/API pipelines with
`RUN_REGRESSION_TESTS=true`. They remain manually playable from other refs.

| Job | Container | Timeout | Purpose |
|-----|-----------|---------|---------|
| `test:login-routing-regression` | `alpine:latest` | 10m | Guards login/2FA routing invariants in `main.rs`, `proton_navigation.rs`, `webview_cookies.rs` |
| `test:sync-regression` | `alpine:latest` | 10m | Guards native sync command, metadata, watcher, and remote-write invariants via `tests/regression/sync.sh` |
| `test:fmt` | `debian:12` | 10m | `cargo fmt --check` |
| `test:clippy` | `debian:12` | 30m | `cargo clippy` lint checks |
| `test:rust` | `debian:12` | 30m | `cargo test` — unit tests for login routing, webview cookies, and live sync |

The same regression checks also run on GitHub via `sanity.yml` (push/PR to
`main`), covering login-routing regression, sync regression, and Rust unit tests
— but no `fmt`, `clippy`, or GitLab Cobertura coverage checks on GitHub. No
package building occurs there.

### Smoke — install and test on real distros (GitLab CI only)

The build containers exist only to link against each distro's libraries. The
VMs are where packages are installed and tested:

- `vm:install:<distro>` copies the package from the matching `build:*` job to
  the VM and installs it with the native package manager (`apt`, `dnf`, `apk`,
  `pacman`).
- `vm:regression:<distro>` runs regression checks and compositor-confirmed
  visual tests on the installed app and collects results and screenshots.

### Build — WebClients once, then 17 distro packages

`build:webclients` runs first (on `node:22`). It checks out the pinned
`WEBCLIENTS_COMMIT`, runs `scripts/build-webclients.sh`, and publishes the result
as `webclients-dist/dist.tar.gz`. The output is distro-independent and is cached
by content, so it is rebuilt only when frontend inputs change. See
[Build Once and Artifact Reuse](./build-deduplication.md).

Each package job runs in a distro-specific container (only so the binary links
against that distro's libraries) and `needs` `build:webclients`. The common flow is:

1. Install system dependencies (compilers, libs, node)
2. Install Rust toolchain
3. Apply distro patch from `patches/<format>/<variant>.patch`
4. Unpack the shared WebClients dist (`scripts/ci/lib/use-webclients-dist.sh`)
5. Sync `package.json` version to `tauri.conf.json` and `Cargo.toml`
6. `npm ci` + `cargo build --release`
7. Package binary and icons into distro format
8. Copy to `artifacts/` directory

| Build job | Container/Image | Output format |
|-----------|-----------------|---------------|
| `build:apk:alpine-3.20` | `alpine:3.20` | `.apk.tar.gz` |
| `build:apk:alpine-3.22` | `alpine:3.22` | `.apk.tar.gz` |
| `build:apk:alpine-3.23` | `alpine:3.23` | `.apk.tar.gz` |
| `build:appimage` | `debian:12` | `.AppImage` |
| `build:aur` | `archlinux:base-devel` | `.pkg.tar.zst` |
| `build:deb:debian-12` | `debian:12` | `.deb` |
| `build:deb:debian-13` | `debian:13` | `.deb` |
| `build:deb:ubuntu-24.04` | `ubuntu:24.04` | `.deb` |
| `build:deb:ubuntu-26.04` | `ubuntu:26.04` | `.deb` |
| `build:flatpak:gnome-49` | `ubuntu:24.04` (extra flatpak layers) | `.flatpak` |
| `build:flatpak:gnome-50` | `ubuntu:24.04` (extra flatpak layers) | `.flatpak` |
| `build:rpm:el10` | `quay.io/centos/centos:stream10` | `.rpm` |
| `build:rpm:fedora-43` | `fedora:43` | `.rpm` |
| `build:rpm:fedora-44` | `fedora:44` | `.rpm` |
| `build:rpm:opensuse-tumbleweed` | `opensuse/tumbleweed:latest` | `.rpm` |
| `build:snap:core24` | `ubuntu:24.04` + `docker:dind` | `.snap` |
| `build:snap:core26` | `ubuntu:24.04` + `docker:dind` | `.snap` |

**Known issues and workarounds:**
- `build:rpm:el10` carries `retry: 1` — the parallel webpack phase can exhaust
  shared runner RAM and get SIGKILL'd; a single automatic retry recovers reliably.
- `build:snap:core26` uses `ghcr.io/canonical/snapcraft:stable` (snapcraft 9.x)
  because the older `8_core24` image returns `Unknown base 'core26'`. The job is
  still marked `allow_failure: true` / `continue-on-error: true` while the
  Canonical snap ecosystem for core26 matures.
- All build jobs have a 2-hour timeout and per-job Rust caches (`.cargo/` +
  `src-tauri/target/`) with a 2-hour TTL.

### Spec

Package specification generation runs in the `spec` stage.

| Job | Output | Container |
|-----|--------|-----------|
| `spec:aur-pkgbuild` | `PKGBUILD` for AUR | `node:22` |
| `spec:rpm-spec` | `proton-drive.spec` for RPM | `node:22` |
| `spec:source-dist` | Source tarball + SHA256 | `alpine/git:latest` |

All spec jobs use `.rules:build` (protected refs/tags/schedules or explicit
`RUN_PACKAGE_BUILDS=true` pipelines, with a manual fallback). Artifacts expire
after 90 days (vs 30 for build artifacts).

### Release

Aggregates artifacts from all 17 build jobs and creates a release.

**GitLab CI** (`release` stage):
- Triggered by `.rules:release` — push to `main` or tags matching `v*`
- Uploads artifacts to the GitLab Generic Package Registry
- Creates a GitLab Release with asset links via `release-cli`
- Collects `.AppImage`, `.deb`, `.rpm`, `.flatpak`, `.snap`, `.pkg.tar.zst`,
  `.apk.tar.gz` from every job's `artifacts/` directory

**GitHub Actions** (`release` job in `package-workflows.yml`):
- Triggered only via `workflow_dispatch` with `workflow: release` input
- Has `needs:` on all 17 build jobs (must all complete)
- Creates a GitHub Release via `.github/actions/maintenance/release/action.yml`
- 360-minute timeout (accounts for waiting on all builds)

### Publish

Manual step for tag pushes only (`.rules:publish` in GitLab, `workflow_dispatch`
with specific `publish-*` input in GitHub).

| Channel | GitLab job | GitHub job | Mechanism | Secrets |
|---------|-----------|-----------|-----------|---------|
| AUR (`aur.archlinux.org`) | `publish:aur` | `publish_aur` | SSH key push | `AUR_SSH_PRIVATE_KEY` |
| Flathub (`github.com/flathub`) | `publish:flatpak` | `publish_flatpak` | SSH key push | `FLATHUB_SSH_PRIVATE_KEY` |
| Snap Store (`snapcraft.io`) | `publish:snap` | `publish_snap` | `snapcraft upload` | `SNAPCRAFT_STORE_CREDENTIALS` |

### GitHub-Only Workflows

These workflows run only on GitHub and have no GitLab equivalent:

| Workflow | Purpose |
|----------|---------|
| `sync-to-gitlab.yml` | Mirror issues, PRs, comments to GitLab |
| `issue-auto-label` (in maintenance/) | Auto-label issues based on content |
| `pr-auto-label` (in maintenance/) | Auto-label PRs based on content |
| `maintenance/release` | Compose release metadata |

### GitHub Workflow Triggers

The `package-workflows.yml` workflow (the package-build mirror) triggers only on:

- `pull_request_target` (opened) — auto-label only
- `issues` (opened) — auto-label only
- `workflow_dispatch` — manual invocation with input parameters (`workflow`, `distro_patch`, `tag`, `version`, `snap_base`, `channel`)

There is **no push, pull_request, schedule, or release trigger** on the package workflow.
All build jobs require `workflow_dispatch`, gated by an `if: github.event_name == 'workflow_dispatch'` condition.

The GitHub `sanity.yml` workflow is manual-only. It no longer runs on every branch push or PR.

Package, spec, release, and publish work is release-gated. GitLab only creates pipelines for semantic `v*` release tags or explicit release-test web/API pipelines with `RUN_RELEASE_TESTS=true`. GitHub package workflows run on `v*` tag pushes or manual dispatch on a `v*` tag ref.

Package, spec, release, and publish jobs are tag-only. In GitLab they require a `v*` tag pipeline. In GitHub, `package-workflows.yml` remains manually dispatched, but package/spec/release/publish jobs additionally require the selected dispatch ref to be a `v*` tag (`refs/tags/v*`).

Package, spec, release, and publish jobs are tag-only. In GitLab they require a `v*` tag pipeline. In GitHub, `package-workflows.yml` remains manually dispatched, but package/spec/release/publish jobs additionally require the selected dispatch ref to be a `v*` tag (`refs/tags/v*`).

Concurrency is grouped by workflow name + branch/ref, cancelling in-progress runs on duplicates.

## Trigger Rules

| Event | GitLab CI | GitHub Actions |
|-------|-----------|----------------|
| PR / MR | No pipeline | No workflow |
| Branch push | No pipeline | No workflow |
| Tag push (`v*`) | Build + spec + release + publish (manual) | Package workflow runs on the tag |
| Main branch push | No pipeline | No workflow |
| Manual dispatch | Release-test pipeline only when `RUN_RELEASE_TESTS=true`; tests only unless the ref is a `v*` tag | Manual workflows only; package/spec/release/publish require a `v*` tag ref |
| Issues opened | — | No workflow |
| Release published | — | No workflow; use tag push/manual dispatch |

## Build Matrix — GitLab ↔ GitHub Mirror

Every GitLab build job has a corresponding GitHub composite action:

| GitHub job | Mirrors GitLab job |
|-----------|-------------------|
| `build_apk_alpine_3_20` | `build:apk:alpine-3.20` |
| `build_apk_alpine_3_22` | `build:apk:alpine-3.22` |
| `build_apk_alpine_3_23` | `build:apk:alpine-3.23` |
| `build_appimage` | `build:appimage` |
| `build_aur` | `build:aur` |
| `build_deb_debian_12` | `build:deb:debian-12` |
| `build_deb_debian_13` | `build:deb:debian-13` |
| `build_deb_ubuntu_24_04` | `build:deb:ubuntu-24.04` |
| `build_deb_ubuntu_26_04` | `build:deb:ubuntu-26.04` |
| `build_flatpak_gnome_49` | `build:flatpak:gnome-49` |
| `build_flatpak_gnome_50` | `build:flatpak:gnome-50` |
| `build_rpm_el10` | `build:rpm:el10` |
| `build_rpm_fedora_43` | `build:rpm:fedora-43` |
| `build_rpm_fedora_44` | `build:rpm:fedora-44` |
| `build_rpm_opensuse_tumbleweed` | `build:rpm:opensuse-tumbleweed` |
| `build_snap_core24` | `build:snap:core24` |
| `build_snap_core26` | `build:snap:core26` |

Each GitHub composite action lives at:
`.github/workflows/<type>/<variant>/action.yml`

GitHub additionally generates package specs via three jobs under
`generate_package_specs_*` (mirroring the GitLab `spec` stage), and runs
issue/PR auto-label and sync-to-gitlab workflows that have no GitLab analog.

The `release` job on GitHub has `needs:` on all 17 build jobs, matching the
GitLab release stage's `needs:` list.

## CI Scripts

### `tests/regression/sync.sh`

A pre-flight gate that guards native sync invariants in the Rust sources. It
checks command registration, sync metadata privacy markers, watcher/poller
contracts, and bounded remote write behavior.

**Environment variables:**
- `PROTOND_REPO_ROOT` — repo root (default: `.`)
- `PROTOND_CI_MODE` — `gitlab`, `github`, or `auto` (default: auto-detect
  from CI env vars)
- `PROTOND_COMPARE_SRC` — `gitlab` or `github`; which system is the source
  of truth (default: `gitlab`)

**Exit codes:**
- `0` — no regressions (all targets present in both systems)
- `1` — regression detected (missing target, misaligned stage)
- `2` — configuration error (missing yq/jq, broken files)

**Dependencies:** `bash >= 4.0`, `yq v4+`, `jq >= 1.6`

### `scripts/ci/lib/write-artifact-manifest.sh`

Scans a build output directory and writes a JSON manifest listing every
artifact (filename, size, SHA256, MIME type). Consumed by release/publish
steps to verify all expected artifacts are present before signing or uploading.

**Usage:**
```bash
./scripts/ci/lib/write-artifact-manifest.sh target/release/ manifest.json
```

**Exit codes:**
- `0` — manifest written successfully
- `1` — artifact directory does not exist
- `2` — no artifacts found
- `3` — output file not writable or invalid JSON

**Output format:**
```json
{
  "build_id": "<CI_JOB_ID or GITHUB_RUN_ID or local-timestamp>",
  "created_at": "2026-05-28T08:00:00Z",
  "artifacts": [
    {
      "name": "protondrive-1.2.3-x86_64.AppImage",
      "path": "dist/protondrive-1.2.3-x86_64.AppImage",
      "size_bytes": 12345678,
      "sha256": "abcdef...",
      "mime_type": "application/x-iso9660-appimage"
    }
  ]
}
```

### Other CI Scripts

Build logic is defined inline in `.gitlab-ci.yml` (`build:webclients` plus the `build:*` package jobs). The remaining
CI scripts are split into subdirectories under `scripts/ci/`:

| Directory | Contents |
|-----------|---------|
| `scripts/ci/build/` | `aur-package.sh` — AUR package build |
| `scripts/ci/install/<distro>/` | Per-distro install scripts run on VMs |
| `scripts/ci/transfer/<distro>/` | Per-distro SCP transfer scripts |
| `scripts/ci/vmtest/<distro>/` | Per-distro GUI load + regression test scripts |
| `scripts/ci/lib/` | Shared helpers: `_vm_common.sh`, `_test_common.sh`, `gui-load-check.sh`, `ui-test-compositor.sh`, `install-rust.sh`, `fetch-latest-artifact.sh`, `write-artifact-manifest.sh` |

Executable test cases are kept under `tests/`, not `scripts/ci/`:

| Directory | Contents |
|-----------|----------|
| `tests/regression/` | Shell regression guards for login routing, sidebar patches, and native sync invariants |
| `tests/unit/` | Python unit tests for local helper logic |
| `tests/robot/` | Robot Framework suites, resources, and VM variables |

**openSUSE Tumbleweed install note:** The RPM package declares
`Requires: libayatana-appindicator-gtk3` (the Fedora capability name). openSUSE
packages the same library under a different name, causing `zypper` to reject the
install. The install script uses `rpm -i --nodeps --force` instead — the library
is present at runtime on openSUSE TW despite the capability name mismatch.

## Cross-Distro Patch System

Each OS variant has a patch file in `patches/<format>/<variant>.patch` that
adapts the WebClients checkout for that distro. The patch application strategy
varies by format:

| Patch directory | Apply strategy |
|----------------|---------------|
| `patches/apk/` | Idempotent: `git apply --reverse --check` then `git apply` |
| `patches/appimage/` | Direct: `git apply` (error if missing) |
| `patches/aur/` | Direct: `git apply` (error if missing) |
| `patches/deb/` | Direct: `git apply` (warning if missing) |
| `patches/flatpak/` | Direct: `git apply` (warning if missing) |
| `patches/rpm/` | Idempotent for EL10, Fedora, openSUSE |
| `patches/snap/` | Idempotent: `git apply --reverse --check` then `git apply` |

## Issue and PR Mirroring: GitHub → GitLab

The `sync-to-gitlab.yml` workflow ensures GitLab-side contributors see the
full discussion history:

- **Issues** — Created/updated in GitLab with `[GH#N]` prefix. State changes
  mirrored.
- **Pull requests** — Synced as GitLab issues with `[GH-PR#N]` prefix and
  `github-pr` label.
- **Comments** — Posted as GitLab notes on the corresponding mirrored issue.
  Deletions are skipped.
- **Credentials** — Uses `GITLAB_SYNC_TOKEN` secret, targets
  the self-hosted GitLab instance.

## Security Notes

- Snap builds require `docker:dind`. The GitLab runner must have
  `privileged = true` in its config.
- AUR publish uses SSH keys (`AUR_SSH_PRIVATE_KEY`) to push to
  `aur@aur.archlinux.org`.
- Flathub publish uses SSH keys (`FLATHUB_SSH_PRIVATE_KEY`) to push to
  `git@github.com:flathub/com.proton.drive.git`.
- Snap Store publish uses `SNAPCRAFT_STORE_CREDENTIALS` with
  `snapcraft upload`.
- All build artifacts expire after 30 days; spec artifacts expire after 90.
- Scripts clean up SSH keys in `after_script` blocks.

## Local vs CI

You can reproduce most CI build steps locally:

| Step | CI equivalent | Local command |
|------|--------------|---------------|
| WebClients build | `scripts/build-webclients.sh` | Same script |
| Version sync | Inline sed commands | Same sed commands |
| Rust build | `cargo build --release` | `cd src-tauri && cargo build --release` |
| Patch application | `git apply patches/<type>/<variant>.patch` | Same |
| Sync regression | `tests/regression/sync.sh` | Same script |
| Artifact manifest | `scripts/ci/write-artifact-manifest.sh` | Same script |
| DEB package | `npx tauri build --bundles deb` | Same (needs system deps) |
| RPM package | `npx tauri build --bundles rpm` | Same (needs system deps) |
| AUR package | `scripts/ci/build/aur-package.sh` | Same (needs Arch tooling) |
| APK archive | Inline tar commands | Manual tar of staged dir |
| Flatpak bundle | `flatpak-builder` commands | Same (needs flatpak tooling) |
| AppImage | `appimagetool` commands | Same |

Most build jobs require the distro-specific dependencies and Rust toolchain.
To run a full build locally without installing dependencies, use the docker
command from the CI job:
```bash
docker run --rm -v "$PWD:/workspace" -w /workspace <image> bash -c '
  apt-get update && apt-get install -y <deps> && scripts/build-webclients.sh && ...'
```

## Adding a New Build Target

1. **GitLab CI first** — add the job to `.gitlab-ci.yml` using the
   `.rules:build` template, distro-specific container image, and version/patch
   extraction logic. See `docs/build-packaging/new-build-checklist.md`.
2. **GitHub mirror** — create a composite action at
   `.github/workflows/<type>/<variant>/action.yml` and register it in
   `package-workflows.yml`.
3. **Release stage** — add the new build job to `release`'s `needs` list in
   both `.gitlab-ci.yml` and `package-workflows.yml`.
4. **Publish (if applicable)** — add a `publish:` job to `.gitlab-ci.yml` and
   an optional publish action under `.github/workflows/`.

## Quick Reference

| Need | System | File |
|------|--------|------|
| Review build pipeline definition | GitLab CI | `/.gitlab-ci.yml` |
| Review GitHub mirror of build matrix | GitHub Actions | `/.github/workflows/package-workflows.yml` |
| Inspect a specific build action | GitHub Actions | `/.github/workflows/<type>/<variant>/action.yml` |
| View issue/PR sync rules | GitHub Actions | `/.github/workflows/sync-to-gitlab.yml` |
| View auto-label rules | GitHub Actions | `/.github/actions/maintenance/` |
| Understand build fan-out and reuse | GitLab CI | `build:webclients` and `docs/ci-cd/build-deduplication.md` |
| Add a new build target | Both | `docs/build-packaging/new-build-checklist.md` |
| Understand packaging conventions | Docs | `docs/build-packaging/packaging.md` |
| Inspect CI VM scripts | GitLab CI | `scripts/ci/{install,transfer,vmtest,lib}/` |
| Check native sync invariants | Both | `tests/regression/sync.sh` |
| Generate artifact manifest | Both | `scripts/ci/lib/write-artifact-manifest.sh` |

## Known Gaps

| Gap | Impact | Tracked in |
|-----|--------|-----------|
| No artifact signing | Users cannot verify download provenance | Roadmap |
| No SBOM | Downstream packagers cannot validate deps | Roadmap |
| Snap core26 `allow_failure` | Builds with `ghcr.io/canonical/snapcraft:stable`; marked non-blocking while core26 ecosystem stabilises | Roadmap |
| First-build cliff on new branches | CI-only change on a brand-new branch fails artifact fetch (404) | `fetch-latest-artifact.sh` error message guides fix |
| No artifact source-state cross-check | Fetched artifact is not verified against current Cargo.lock hash | Low risk; only affects CI-only commits |
| Docs commits run vmtest | Only builds have `changes:` gates; vmtest runs on all commits conservatively | Acceptable; add `changes:` to transfer base if runner cost grows |
| openSUSE RPM dependency mismatch | `libayatana-appindicator-gtk3` capability name differs on TW; install uses `--nodeps` workaround | Fix RPM spec to use conditional `%if` for openSUSE |
