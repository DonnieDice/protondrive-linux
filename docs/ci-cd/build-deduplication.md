# Build Once and Artifact Reuse

> How the GitLab pipeline avoids repeating expensive work: the WebClients
> frontend is built once and shared by every package job, finished packages are
> reused by content key, and VMs are used only to install and test.

## Roles

| Layer | Where it runs | Purpose |
|-------|---------------|---------|
| `build:webclients` | GitLab runner (`node:22` container) | Build the Proton frontend once. Distro-independent. |
| `build:<format>:<target>` (17 jobs) | GitLab runner, distro container | Compile the Rust/Tauri app against that distro's libraries, apply the distro patch, produce the package. |
| `vm:install:*`, `vm:regression:*`, `smoke:*` | Target VMs over SSH (or the runner for `smoke:*`) | Install the finished package on the real distro and run regression and GUI-load tests. |
| `release`, `publish:*`, `mirror:github` | GitLab runner | Collect artifacts, publish, and mirror an allowlisted tree to GitHub. |

Containers exist only so each package links against the right system libraries
(WebKitGTK 4.1, GTK, glibc or musl). They are not the test environment: the VMs are.

## Why the frontend is built separately

The WebClients webpack build takes about 100 minutes and its output
(`WebClients/applications/drive/dist`, which `src-tauri/tauri.conf.json` serves
as `frontendDist`) does not depend on the distro, the Rust toolchain or the
package format. Previously each of the 17 package jobs repeated it.

Now:

1. `build:webclients` runs `scripts/ci/lib/fetch-webclients.sh` (pinned to
   `WEBCLIENTS_COMMIT`) and `scripts/build-webclients.sh`, then packs the result
   into `webclients-dist/dist.tar.gz`.
2. Every package job declares `needs: [build:webclients]` (set once on
   `.rules:build`) and calls `scripts/ci/lib/use-webclients-dist.sh`, which
   unpacks the archive into `WebClients/applications/drive/dist`. Package jobs
   never clone or build WebClients.
3. `build:webclients` runs automatically on merge requests, branches and tags.
   Package jobs are automatic on tags and `main`, and manual elsewhere.

## Content-addressed reuse

`scripts/ci/lib/compute-build-key.sh` produces a deterministic key from tracked
Git blobs (`git ls-files -s`) plus build-affecting environment values:

```text
<package-type>-<target-label>-<sha256>
```

`scripts/ci/lib/build-artifact-cache.sh` uses that key as the version of a
`proton-drive-build-cache` package in the GitLab Generic Package Registry:

- `restore` (in `before_script`) downloads and verifies the archive for the
  exact key (embedded key and SHA-256 checksums). On a hit the job exits
  successfully before installing any toolchain.
- `publish` (in `after_script`) uploads the verified output on success. Upload
  failures are warnings; the job artifact stays authoritative.

Because reuse is keyed by inputs rather than pipeline status, a fix pipeline
reuses outputs from earlier pipelines, including failed or canceled ones.

The `webclients` package type is keyed **only** on frontend inputs
(`scripts/build-webclients.sh`, the `fix_deps`/`create_stubs`/`patch_drive_linux_*`
scripts, `patches/common`, `WEBCLIENTS_COMMIT`, `WEBCLIENTS_REF`, `NODE_OPTIONS`).
Rust, toolchain or packaging changes therefore never invalidate it. Its archive
lives in `webclients-dist/` (`BUILD_ARTIFACT_DIR`) so it cannot be mistaken for a
finished package in `artifacts/`.

Controls: `FORCE_REBUILD=true` bypasses all hits; `REUSE_BUILD_ARTIFACTS=false`
disables lookup and publication.

## Pipeline hygiene

- A push to a branch that has an open merge request creates only the merge
  request pipeline (`workflow:rules` skips the duplicate branch pipeline).
- `auto_cancel: on_new_commit: interruptible` cancels superseded runs.
- Branch tips already merged should not keep pipelines running; cancel them.

## Failure modes

| Scenario | Behaviour |
|----------|-----------|
| Frontend inputs unchanged | `build:webclients` restores from the registry in seconds |
| Frontend inputs changed | `build:webclients` runs the full build once for the whole pipeline |
| `build:webclients` fails | Package jobs do not start (their `needs` is unmet) |
| Package inputs unchanged | The package job restores its verified artifact and exits early |
| Registry unavailable | Warnings only; jobs build normally |

## Files

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | `build:webclients`, the 17 package jobs, `.rules:build`, `.use_webclients_dist` |
| `.gitlab-ci-vm-tests.yml` | `vm:install:*`, `vm:regression:*` and related VM jobs |
| `scripts/ci/lib/use-webclients-dist.sh` | Unpack the shared dist in package jobs |
| `scripts/ci/lib/fetch-webclients.sh` | Pinned WebClients checkout |
| `scripts/ci/lib/compute-build-key.sh` | Deterministic content key |
| `scripts/ci/lib/build-artifact-cache.sh` | Verified registry restore/publish |
