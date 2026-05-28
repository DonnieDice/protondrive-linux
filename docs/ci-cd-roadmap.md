# CI/CD Roadmap — Proton Drive Linux

> High-level roadmap for the CI/CD pipeline. Documents current capability,
> completed milestones, and planned improvements.
>
> Companion to: [`ci-pipeline-reference.md`](ci-pipeline-reference.md) (detailed
> GitLab job reference) and [`workflow.md`](workflow.md) (contributor workflow).

---

## Current State (Snapshot)

The project runs **two CI systems** in parallel:

| System | Entrypoint | Purpose |
|--------|-----------|---------|
| **GitHub Actions** | `.github/workflows/package-workflows.yml` | Primary — build, package, release, publish |
| **GitLab CI** | `.gitlab-ci.yml` | Mirror — same package builds on GitLab infrastructure |

Both systems execute the same build matrix. A **`sync-to-gitlab.yml`** workflow
mirrors GitHub issues, PRs, and comments to a GitLab instance for backup.
**Dependabot** is configured for dependency updates.

### Pipeline Stages (Both Systems)

```
Build (17 jobs) → Spec/GitLab only → Release → Publish
```

#### Build — 17 distro packages

| Format | Variants |
|--------|----------|
| APK | Alpine 3.20, 3.22, 3.23 |
| AppImage | linux-baseline (portable) |
| AUR | Arch Linux rolling |
| DEB | Debian 12, Debian 13, Ubuntu 24.04, Ubuntu 26.04 |
| Flatpak | GNOME 49, GNOME 50 |
| RPM | CentOS Stream 10, Fedora 43, Fedora 44, openSUSE Tumbleweed |
| Snap | Core 24, Core 26 (allow_failure) |

All build jobs: install deps → clone WebClients → apply distro patch →
build web clients → npm install → cargo build → package → `artifacts/`.

#### Spec (GitLab CI only)

- `spec:aur-pkgbuild` — generates `PKGBUILD`
- `spec:rpm-spec` — generates `.spec` file
- `spec:source-dist` — creates source tarball + SHA-256

#### Release

- **GitLab**: aggregates 17 build artifacts → uploads to Generic Packages →
  creates GitLab Release via `release-cli`
- **GitHub**: aggregates artifacts → creates GitHub Release via
  `.github/workflows/maintenance/release`

#### Publish

| Channel | Both systems | Secrets needed |
|---------|:-----------:|----------------|
| AUR (aur.archlinux.org) | Yes | `AUR_SSH_PRIVATE_KEY` |
| Flathub (flathub.org) | Yes | `FLATHUB_SSH_PRIVATE_KEY` |
| Snap Store (snapcraft.io) | Yes | `SNAPCRAFT_STORE_CREDENTIALS` |

### Trigger Rules

| Event | What runs |
|-------|-----------|
| PR / branch push | All build jobs + all spec jobs |
| Tag push (`v*`) | Full pipeline: build → spec → release → publish |
| Main branch push | Build + spec + release (no publish) |
| Manual dispatch | Any job group via `workflow_dispatch` |

### Cross-Distro Patch System

Each OS variant has a patch file in `patches/<format>/<variant>.patch` that
adapts the WebClients checkout. APK and EL10 patches apply idempotently
(`--reverse --check` first). Missing patches emit warnings or errors depending
on format.

---

## ✅ Completed Milestones

- [x] **17-package build matrix** — every major Linux packaging format represented
- [x] **Dual CI redundancy** — GitLab CI mirrors GitHub Actions for availability
- [x] **Automated releases** — tagged releases produce downloadable artifacts on both GitLab and GitHub
- [x] **Automated publishing** — AUR, Flathub, and Snap Store updates happen automatically on tag
- [x] **Package spec generation** — PKGBUILD, RPM `.spec`, and source tarballs auto-generated
- [x] **Distro patch system** — per-distribution WebClients patches with idempotent apply
- [x] **Cross-platform Rust caching** — per-job `.cargo` + `target/` caches (2h TTL)
- [x] **Issue/PR sync** — GitHub ↔ GitLab bidirectional mirroring
- [x] **Dependabot** — automated dependency update PRs
- [x] **Contributor workflow docs** — `workflow.md`, `CONTRIBUTING.md`, `ci-pipeline-reference.md`
- [x] **Branch-based auto-labeling** — `feature/` → `enhancement`, `fix/` → `bug`, `chore/` → `chore`

---

## 🔜 Near-Term (Next 1-2 Months)

### Code Quality Gates

- [ ] **Unit test runner** — add a `test` job (plain `cargo test`) to both CI systems
- [ ] **Lint / format check** — run `cargo fmt --check` and `cargo clippy` on PRs
- [ ] **Review bot integration** — CodeRabbit / Qodo is mentioned in workflow.md but not wired into CI commit status gates

### Signing & Supply Chain

- [ ] **Artifact signing** — GPG/signify signing of `.AppImage`, `.deb`, `.rpm`, `.snap` artifacts
- [ ] **Checksum manifest** — produce `SHA256SUMS` or `SHA256SUMS.asc` alongside releases
- [ ] **SBOM generation** — `cargo cyclonedx` or `cargo auditable` for software bill of materials

### CI Hygiene

- [ ] **Shared Rust cache** — one cache namespace across all jobs instead of per-formula caches
- [ ] **Better failure diagnostics** — structured artifact failure output (currently just grep logs)
- [ ] **Retry flaky builds** — network timeout retry already in openSUSE; extend to APK/DNF jobs

---

## 🗺 Medium-Term (3-6 Months)

### Testing Infrastructure

- [ ] **Integration tests** — headless Tauri test suite (`tauri-driver` or WebDriver)
- [ ] **VM-level smoke tests** — boot each package format in its native distro container, verify `--version`
- [ ] **Cross-arch builds** — arm64 for Apple Silicon / Raspberry Pi via QEMU emulation

### Release Automation

- [ ] **Auto-changelog** — derive release notes from conventional commits since last tag
- [ ] **Homebrew tap publish** — automate `brew tap protondrive-linux` formula push
- [ ] **Docker image publish** — push `protondrive-linux` images to GHCR for headless testing

### Security Hardening

- [ ] **Container image scanning** — Trivy or Grype scan of build containers
- [ ] **Dependency auditing** — `cargo audit` / `npm audit` in CI
- [ ] **SAST scanning** — `cargo deny` for license + advisory checks
- [ ] **FIPS-compatible build** — verify Alpine musl build compiles without OpenSSL FIPS violations

---

## 🚀 Long-Term (6+ Months)

### Service Migrations

- [ ] **Unified CI entrypoint** — one pipeline driving both GitHub and GitLab from shared YAML (e.g., `pipeline.yml` referenced via includes)
- [ ] **Self-hosted runner pool** — reduce reliance on GitHub/GitLab shared runners for 2h builds
- [ ] **Matrix UI** — visual dashboard showing per-distro tier: stable / beta / dev

### Quality of Life

- [ ] **PR preview builds** — comment on PRs with "Download Alpine 3.22 APK" links
- [ ] **CI regression telemetry** — track build duration / failure rate per job over time
- [ ] **Cross-distro compatibility map** — auto-detected WebKitGTK version vs. features matrix

---

## Known Gaps

| Gap | Impact | Tracked |
|-----|--------|---------|
| No unit tests in CI | Silent regressions in Rust and JS code | — |
| No artifact signing | Users cannot verify provenance of downloads | — |
| No SBOM | Downstream packagers (Debian, Fedora) cannot validate dependencies | — |
| No VM/integration tests | AppImage/Flatpak/Snap might work in build env but not in target | — |
| Snap core26 `allow_failure` | Latest Ubuntu snap base is untested | — |
| No shared Rust cache between jobs | Each of 17 jobs rebuilds deps independently; ~2h each | — |

---

## CI File Index

| File | Lines | Purpose |
|------|-------|---------|
| `.gitlab-ci.yml` | 1,492 | GitLab CI: build → spec → release → publish |
| `.github/workflows/package-workflows.yml` | 601 | GitHub Actions: build → release → publish |
| `.github/workflows/sync-to-gitlab.yml` | 130 | Issue/PR/comment mirror to GitLab |
| `.github/workflows/maintenance/` | — | Release, auto-label, package-spec generators |
| `.github/workflows/{apk,appimage,aur,deb,flatpak,rpm,snap}/**/action.yml` | — | Per-formula composite action implementations |
| `patches/{apk,appimage,aur,deb,flatpak,rpm,snap}/*.patch` | — | Distro-specific WebClients patches |
