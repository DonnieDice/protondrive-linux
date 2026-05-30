---
title: "New Build/Package Checklist"
created: 2026-05-28
updated: 2026-05-28
type: guide
tags: [build, packaging, release]
sources:
  - []
---


# New Build/Package Checklist

Use this checklist when adding a new package target to the ProtonDrive Linux
build and release pipeline. It records every step taken and every decision made
so the process is repeatable and auditable.

## Pre-Work: Verify Compatibility Gates

Before investing any build work, confirm both compatibility gates pass on the
target:

- [ ] **libc gate**: glibc >= 2.35 (or musl for Alpine APK targets).
  - On a glibc host: run `ldd --version` and record the version.
  - On a musl host: run `apk info musl` and record the version.
  - If the host uses a runtime (Flatpak, Snap), record the runtime name and
    version instead.

- [ ] **WebKitGTK gate**: WebKitGTK 4.1 (with GTK 3) must be available and
  **installed** in the target repos or runtime.
  - Do not rely on repo search alone. Verify the library is actually shipped
    and installable: `apk info -e webkit2gtk-4.1`, `dpkg -l
    libwebkit2gtk-4.1-0`, `rpm -q webkit2gtk4.1`, or equivalent.
  - Record the exact WebKitGTK package version found.
  - If WebKitGTK 4.1 is not available or not installed, the target is a legacy
    candidate or not-primary — do not proceed with a full build pipeline.

- [ ] **Record findings**:
  - Date of check:
  - Target distro and version:
  - libc version and type (glibc / musl / runtime):
  - WebKitGTK 4.1 version (or "not available"):
  - Both gates pass? (yes / no):

### Example: Alpine 3.20 reclassification (2026-05-15)

The compatibility map originally listed Alpine 3.20 as `not-primary` with
`webkitgtk: fail`. On inspection of an actual Alpine 3.20 host, WebKitGTK 4.1
v2.44.1 was both available in repos and installed at
`/usr/lib/libwebkit2gtk-4.1.so.0.13.5`. The gate was corrected from `fail` to
`pass`, and Alpine 3.20 was reclassified from `not-primary` to
`roadmap-patch-ready`.

This is why the "installed, not just available" check matters: a repo search
may miss packages that are already shipped in the base install or community
repos, and the compatibility map can lag behind reality.

## Step 1: Create the Distro Patch

- [ ] Create `patches/<package>/<target>.patch` against the clean repository
  base.
  - The patch replaces the clean `fn main()` WebKitGTK comment block in
    `src-tauri/src/main.rs` with the target-specific environment variables.
  - Follow the pattern of existing patches (e.g., `apk/alpine.3.22.patch`,
    `deb/debian.12.patch`, `rpm/opensuse.tumbleweed.patch`).
  - Use the same WebKitGTK conservative path variables for musl targets:
    `WEBKIT_DISABLE_DMABUF_RENDERER=1`,
    `WEBKIT_DISABLE_COMPOSITING_MODE=1`,
    `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`,
    `JSC_useWasmIPInt=false`, `GDK_GL=disable`,
    `LIBGL_ALWAYS_SOFTWARE=1`, `GSK_RENDERER=cairo`.
  - For musl/Alpine APK targets, the patch must also set up the D-Bus session
    bus and `AT_SPI_BUS_ADDRESS` workarounds — see the Notes section for
    details. Alpine's musl lacks systemd's auto-launching, so the patch must
    auto-launch a user D-Bus session if the inherited bus is not accessible.
- [ ] Verify the patch applies cleanly: `git apply --check
  patches/<package>/<target>.patch`.
- [ ] Verify the reverse check works: `git apply --reverse --check
  patches/<package>/<target>.patch` (after applying, to confirm reversibility).

## Step 2: Update the Compatibility Map

- [ ] Add or update the target entry in
  `packaging/compatibility-map.yml`.
  - If the target was previously in `not_primary` or `legacy_candidates`,
    reclassify it: update the status, gates, and reason fields, and add it to
    the appropriate section (`roadmap_patch_ready` or the release-gated
    section).
  - Set `workflow` to the package implementation path under
    `.github/workflows/<package>/<target>` (or `null` if no implementation
    exists yet).
  - Set `build_container` to the correct container image.
  - Set `release_label`, `artifact_name`, and `patch` to match the naming
    convention.
  - List supported distro versions under `supports`.
  - List remaining requirements under `before_release_gate`.

## Step 3: Create the GitHub Actions Implementation

- [ ] Create `.github/workflows/<package>/<target>/action.yml`.
  - Use an existing implementation as a template (e.g.,
    `.github/workflows/deb/debian-12/action.yml`,
    `.github/workflows/rpm/opensuse-tumbleweed/action.yml`).
  - Set the container image to match the target distro.
  - Install all build dependencies in the container (compiler, WebKitGTK dev
    packages, GTK dev packages, Node.js, etc.).
  - Apply the distro patch.
  - **For musl (Alpine APK) targets only**: Before the build step, configure
    `.cargo/config.toml` with `linker = "gcc"` and
    `target-feature=-crt-static` to allow dynamic linking against shared
    system libraries. See the Notes section for the exact config and an
    explanation of the musl self-contained linking issue.
  - Build the frontend (`scripts/build-webclients.sh`).
  - Build the Tauri binary (`npx tauri build --verbose`). For Alpine APK
    targets, use `cargo build --release` directly instead — APK packaging is
    handled in a separate step and the Tauri bundler defaults to deb/rpm
    targets not available in Alpine containers.
  - Package the output in the correct format (DEB, RPM, APK tarball, etc.).
  - Normalize the artifact filename with the target label.
  - Upload the artifact with a unique name.

- [ ] Add a matching job to `.github/workflows/package-workflows.yml`.
  - Set the job `name` to the exact target, not a generic package family.
  - Set the job `uses` path to the new implementation folder.
  - Set any target env values, container image, secrets, and dependencies in
    the entrypoint job.

- [ ] Verify the entrypoint triggers the job on `push` to `main`, `alpha`,
  package branches, tags, pull requests, and `workflow_dispatch`.

## Step 4: Create the Local CI Build Script (Optional)

Local CI build scripts exist only for targets that benefit from local
iteration (currently Alpine APK and AUR targets). For DEB, RPM, Flatpak, Snap,
and AppImage targets, CI runs are handled entirely in GitHub Actions.

- [ ] If a local CI script is warranted, create
  `scripts/ci/build-<target>-<package>.sh`.
  - Use an existing script as a template (e.g.,
    `scripts/ci/build-opensuse-tumbleweed-rpm.sh`,
    `scripts/ci/build-alpine-322-apk.sh`).
  - The script should create a clean git worktree, apply the patch, build, and
    copy the artifact to an output directory.
  - Make it executable: `chmod +x scripts/ci/build-<target>-<package>.sh`.

## Step 5: Integrate with Release

- [ ] Add the new job to the release gate in
  `.github/workflows/package-workflows.yml`.
- [ ] Add an artifact download step for the new target.
- [ ] Add the new file extension to the `find` command in "Prepare release
  files".
- [ ] Add a filename normalization case if needed (e.g., for RPM suffix
  disambiguation).
- [ ] Add the target to the release notes download table.
- [ ] Add an installation section to the release notes.

## Step 6: Update Documentation

- [ ] Update `docs/build-packaging/packaging.md`:
  - Add or move the target in the support matrix tables.
  - Update the patch tree diagram.
  - Update compatibility notes and rules.
  - Update the upstream baseline check section with the new findings.
- [ ] Update `patches/README.md`:
  - Add the new patch to the full patch tree diagram.
  - Add the patch to the roadmap patch-ready table (or move it to
    release-gated if fully promoted).
- [ ] Update `docs/release-checklist.md`:
  - Add the new package target to the "All builds are green" checklist.

## Step 7: Push and Validate

- [ ] Commit all changes on a feature branch.
- [ ] Push the feature branch to remote.
- [ ] Confirm the new GitHub Actions job triggers and passes.
- [ ] Download the workflow artifact.
- [ ] Install and test the artifact on the target host (runtime smoke test).
  - The app must launch and display the Proton Drive login page.
  - The WebKitGTK webview must render without a white screen or crash.
  - If the app fails to render, try the WebKitGTK environment workarounds
    from the README: `WEBKIT_DISABLE_DMABUF_RENDERER=1
    WEBKIT_DISABLE_COMPOSITING_MODE=1`.

## Step 8: Promote to Release-Gated (After Smoke Test Passes)

- [ ] Update `packaging/compatibility-map.yml`: change status to
  `release-gated`, set `runtime_smoke.status: pass`, add evidence.
- [ ] Update `docs/build-packaging/packaging.md`: move the target to the release-gated table.
- [ ] Update `patches/README.md`: move the patch to the release-gated list.
- [ ] Update `docs/release-checklist.md` if needed.
- [ ] Merge the promotion through a pull request into `main`.

## Notes and Lessons Learned

Record anything unexpected discovered during the process:

- **WebKitGTK availability vs installation**: The compatibility map listed
Alpine 3.20 as `not-primary` with `webkitgtk: fail`, but WebKitGTK 4.1 was
both available in repos and already installed on the host. Always verify on
the actual target system — repo metadata and documentation can be stale.
- **musl vs glibc**: Alpine APK targets do not need a glibc minimum check.
The musl gate is separate and always passes for Alpine targets.
- **Patch indentation**: Rust source uses 4-space indentation. Diff hunks must
match the exact whitespace or `git apply` will reject the patch.
- **Alpine `-dev` packages and transitive deps**: Alpine's `-dev` packages
don't automatically pull in all transitive dev libraries (unlike Debian's
`-dev` packages which depend on their transitive deps). You must explicitly
install `glib-dev`, `harfbuzz-dev`, `cairo-dev`, `pango-dev`, `gdk-pixbuf-dev`,
`wayland-dev`, `zlib-dev`, `libintl`, and `musl-dev` alongside
`webkit2gtk-4.1-dev` and `gtk+3.0-dev`.
- **Alpine package name differences**: Some Alpine packages have different
names than their Debian/RPM counterparts: `libayatana-appindicator-dev` (not
`libappindicator-dev`), `vips-dev` (not `libvips-dev`).
- **Alpine system cargo is too old**: Alpine 3.20's system `cargo` (1.78.0)
does not support `edition2024` used by the `time-core` dependency. Always
use rustup to install a current stable Rust toolchain instead of Alpine's
system packages.
- **musl self-contained linking (CRITICAL)**: When rustc targets
`x86_64-unknown-linux-musl`, it defaults to `-crt-static` which produces
`-static-pie` binaries. This forces the linker to look for `.a` static
archives only, but GTK/WebKit libraries are only available as `.so` shared
objects on Alpine. The fix requires a `.cargo/config.toml`:
  ```toml
  [target.x86_64-unknown-linux-musl]
  linker = "gcc"
  rustflags = ["-C", "target-feature=-crt-static"]
  ```
  - `linker = "gcc"`: Makes rustc invoke gcc as the linker wrapper, which
    properly searches `/usr/lib` for system libraries (the musl `ld` used
    by rustc's self-contained mode has limited search paths).
  - `target-feature=-crt-static`: Disables static PIE linking so the binary
    can dynamically link against shared system libraries (GTK, WebKit, etc.).
  - Do NOT use `link-self-contained=no` alone — Alpine doesn't provide
    `libunwind` as a separate package, and the self-contained mode provides
    CRT/unwind from the rust sysroot. The combination of `linker=gcc` +
    `-crt-static` preserves the self-contained CRT/unwind bits while
    allowing dynamic linking for system libraries.
  - **Note**: This `.cargo/config.toml` is currently documented here but not
    yet committed to the repository. For CI builds, create it in the container
    or action step before the build. Consider committing it to the repo if it
    becomes needed across multiple targets.
- **Tauri bundler on Alpine**: `npx tauri build` defaults to `deb`, `rpm`,
`appimage` bundle targets which require `xdg-open` and other tools not
available in a minimal Alpine container. For APK targets, use `cargo build
--release` directly instead of `npx tauri build`, since APK packaging is
handled in a separate step.
- **APKBUILD is a file, not a directory**: When creating the APK staging
  directory, do not `mkdir -p "$STAGING/APKBUILD"` — that creates APKBUILD as
  a directory. The APKBUILD should be written as a file with `cat >`.
- **D-Bus session bus on Alpine (CRITICAL)**: Alpine musl lacks systemd's
  D-Bus auto-launching. If `DBUS_SESSION_BUS_ADDRESS` points to an
  inaccessible socket (e.g., owned by lightdm/root), WebKitWebProcess will
  SIGABRT in `g_dbus_address_get_stream_sync()` due to a GLib bug where the
  `autolaunch:` fallback path can fail without setting a GError. The patch
  must auto-launch a user D-Bus session via `dbus-launch --sh-syntax` if the
  inherited bus is not accessible, set `AT_SPI_BUS_ADDRESS=/dev/null` to
  prevent the accessibility bus from crashing, and create `XDG_RUNTIME_DIR`
  if missing. This affects all Alpine APK targets (3.20, 3.22, 3.23).
- **`AT_SPI_BUS_ADDRESS` on Alpine**: The accessibility bus socket inherited
  from a display manager (e.g., lightdm) is typically not accessible to the
  user. Setting `AT_SPI_BUS_ADDRESS=/dev/null` prevents WebKitWebProcess from
  attempting to connect and crashing. This produces a harmless warning but
  avoids the SIGABRT.
- **Patch without workflow**: If a target has a patch but no corresponding
  GitHub Actions workflow (e.g., `patches/rpm/opensuse.leap.16.patch` —
  existing as of 2026-05-28), note it in the compatibility map as
  `workflow: null` and set a `before_release_gate` item to create the
  workflow. For these targets, CI builds and local verification scripts
  cover testing until the workflow is added.
