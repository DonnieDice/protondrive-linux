---
title: "Release Checklist"
created: 2026-05-28
updated: 2026-05-28
type: guide
tags: [release, packaging]
sources:
  - []
---


# Release Checklist

Use this checklist before every release deployment.

Tauri v2 is the current framework for this project.

---

## 1. Version Bump

The release version is tracked in three files — all must be updated to match.

- [ ] `package.json` — update `version` field to the new version.
- [ ] `src-tauri/Cargo.toml` — update `[package].version` to match.
- [ ] `src-tauri/tauri.conf.json` — update the top-level `version` field to match.
- [ ] Verify the version string matches across all three files.
- [ ] Commit version bump with message: `chore: bump version to v<x.y.z>`.

> **Note:** Both `version` and `identifier` (e.g. `com.proton.drive`) are **top-level** fields
> in `tauri.conf.json`, not nested under `app`. Do not change the identifier between
> releases — only the `version` field.

---

## 2. Build Web Clients

The Tauri application bundles a frontend from the `WebClients` submodule/source.

- [ ] Run the web client build script to ensure the frontend compiles:
      ```bash
      ./scripts/build-webclients.sh
      ```
- [ ] Verify the output exists at `WebClients/applications/drive/dist/`.

---

## 3. Tauri Native Build (Local Verification)

Build all native bundles locally to catch compile errors before CI.

- [ ] Install prerequisites (if not already present):
      ```bash
      sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file \
        libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
      ```
- [ ] Run the full Tauri build:
      ```bash
      npm run build
      ```
      This runs `./scripts/build-webclients.sh` (bundles the frontend) followed by
      `tauri build --bundles deb,rpm,appimage`, which compiles the Rust backend and
      produces native packages.
- [ ] Verify the generated bundles exist in `src-tauri/target/release/bundle/`.
- [ ] Smoke-test the AppImage on a clean Linux environment.

> **Tauri v2 change:** The bundle configuration moved under the `bundle` key at
> the top level of `tauri.conf.json`. Targets are controlled via the
> `bundle.targets` array (e.g. `["deb", "appimage", "rpm"]`). The old Tauri v1
> `tauri => bundle` nesting no longer applies.

---

## 4. Capabilities & Permissions

Tauri v2 uses a capabilities-based permission system.

- [ ] Verify `src-tauri/capabilities/` contains the correct capability files
      for each platform target.
- [ ] Confirm all required Tauri commands, FS access, shell scopes, and HTTP
      scopes are declared in the relevant capability JSON files.
- [ ] Run `npx tauri info` to validate the Tauri configuration:
      ```bash
      npx tauri info
      ```
      Check for warnings about unresolved IPC commands or missing permissions.

---

## 5. Documentation Update

- [ ] User-facing docs (`docs/`) reflect the release behavior.
- [ ] Install/build/troubleshooting docs are updated where needed.
- [ ] This release checklist is reviewed:
      - [ ] Checklist still matches the current release process.
      - [ ] New release tasks discovered during this cycle are added.
      - [ ] Obsolete release tasks are removed or corrected.

---

## 6. CI / Build Pipeline Checks

All CI builds must be green before proceeding. The project uses **two CI systems**
(GitHub Actions + GitLab CI) that mirror the same build matrix. Check both:

- [ ] **GitHub Actions** — confirm all jobs pass in the `package-workflows.yml` run.
- [ ] **GitLab CI** — confirm the tag pipeline shows all jobs green in **CI/CD > Pipelines**.

Per-target builds (check on either CI system, both must be green):

GitLab CI runs eight stages — confirm each in sequence:

- [ ] **`test` stage** — all 5 jobs pass (fmt, clippy, rust, login-routing, sync).
- [ ] **`build` stage** — all distro builds pass.
- [ ] **`gate` stage** — `build:gate` passes. A skipped gate means a build failed; do not proceed.
- [ ] **`transfer` stage** — artifact SCPed to all 10 VMs.
- [ ] **`install` stage** — package installed on all 10 VMs.
- [ ] **`vmtest` stage** — GUI loads, OCR confirms login screen, regression checks clean on all VMs.
- [ ] **`report` stage** — deployment matrix report generated.

Per-target build checks (both CI systems):

- [ ] **AppImage** — linux-baseline job is passing.
- [ ] **DEB** — Debian 12, Debian 13, Ubuntu 24.04, Ubuntu 26.04 jobs passing.
- [ ] **RPM** — Fedora 43, Fedora 44, EL10, openSUSE Tumbleweed jobs passing.
- [ ] **Flatpak** — GNOME 49 and GNOME 50 jobs passing.
- [ ] **Snap** — core24 passing; core26 is `allow_failure` (non-blocking).
- [ ] **AUR** — Arch Native job is passing.
- [ ] **APK (Alpine)** — 3.20, 3.22, and 3.23 jobs passing.
- [ ] **Release job** — final release pipeline job is passing.
- [ ] **GitHub Actions** — confirm all jobs pass in the `package-workflows.yml` run.

> **CI tip:** The tag pipeline (`v*` tag) is what triggers the final release
> job on both CI systems. Always check the tag-specific pipeline, not a
> branch pipeline, before proceeding.

---

## 7. Package Mapping

- [ ] Release job includes all `pass` status packages from `packaging/compatibility-map.yml`.
- [ ] Roadmap, legacy candidate, and not-primary targets are excluded unless promoted.
- [ ] Release artifacts use stable, unique names.
- [ ] Artifact manifest (`.artifact-manifest.json` or similar) is generated and
      checked into the release assets.

---

## 8. Signing & Checksums

- [ ] DEB/RPM packages are signed with the project GPG key.
- [ ] AppImage is signed (if GPG signing is configured in the pipeline).
- [ ] A `SHA256SUMS` file is generated for all release artifacts.
- [ ] The checksum file itself is signed (`SHA256SUMS.asc`).

---

## 9. Publish Secrets

- [ ] `AUR_SSH_PRIVATE_KEY` secret is set.
- [ ] `SNAPCRAFT_STORE_CREDENTIALS` secret is set.
      **BLOCKED:** snapcraft CLI / Snap Store API inconsistency — publishing on hold.
      See issues #83 and #19.
- [ ] `FLATHUB_SSH_PRIVATE_KEY` secret is set.
- [ ] Flathub initial submission PR has been merged (required before Flatpak
      publish can push updates).
- [ ] GPG signing key passphrase secret is set (if signing is done in CI).

---

## 10. Merge and Tag

- [ ] Merge approved release PR(s) into `main`.
- [ ] Confirm PRs contain only commits intended for the release.
- [ ] Never bypass review by pushing release changes directly.
- [ ] Push `main` after merge: `git push origin main`.
- [ ] Create and push the release tag:
      ```bash
      git tag -a v<x.y.z> -m "Release v<x.y.z>"
      git push origin v<x.y.z>
      ```
      The tag **must** point to `main`.

> **Important:** The tag name must match the version exactly (e.g. `v1.2.3`).
> CI pipelines on both GitHub and GitLab use the tag to determine the release
> version automatically.

---

## 11. Post-Release

- [ ] Verify the GitHub Actions release job completed successfully.
      The release is **automatic** — pushing the tag triggers the release job,
      which collects artifacts, creates a GitHub Release, and uploads assets.
      Only intervene if the job failed.
- [ ] Verify the GitLab CI release pipeline — check
      **CI/CD > Pipelines** on GitLab for the tag pipeline and confirm the
      `release` stage completed.
- [ ] Verify published artifacts on each distribution channel:
      - [ ] AUR package updated (automatic via `publish:aur`).
      - [ ] Snap Store updated (once unblocked).
      - [ ] Flathub updated (automatic via `publish:flatpak`).
      - [ ] GitHub Release page shows all expected `.deb`, `.rpm`, `.AppImage`,
            and any other artifacts.
- [ ] Verify artifact checksums match what was uploaded:
      ```bash
      sha256sum --check SHA256SUMS
      ```
- [ ] Update any downstream references (documentation, website, announcement).

---

## Final Gate

Do not tag or publish until **every checkbox above is complete**.

---

## Quick Reference: Tauri v2 vs v1 Changes

| Area | Tauri v1 (legacy) | Tauri v2 (current) |
|---|---|---|
| Build command | `npx tauri build` (same) | `npx tauri build` (compatible) |
| Config structure | `tauri.bundle.targets` | Top-level `bundle.targets` |
| Permissions | Built-in, minimal | Capabilities files in `capabilities/` |
| WebKitGTK dep | `libwebkit2gtk-4.0-dev` | `libwebkit2gtk-4.1-dev` |
| IPC model | Invoke-only | Invoke + events with scoped permissions |
| Plugin system | Plugins bundled | Separate plugin crates with own capabilities |
