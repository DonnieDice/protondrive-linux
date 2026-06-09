# Build Deduplication and Artifact Reuse

> How the pipeline avoids redundant 2-hour Tauri/Rust builds while still running
> the full transfer → install → vmtest chain on every CI-relevant commit.

## Problem

Each of the 17 build jobs compiles Tauri + Rust from source inside a distro-specific
container. A single build run takes 90–120 minutes. Without deduplication, every
commit — including docs edits, vmtest script tweaks, or CI yml fixes — triggers
all 17 builds before the transfer/install/vmtest chain can run. That is both slow
and wasteful.

## Three-Tier Behaviour

| Commit type | Builds | Transfer/Install/Vmtest |
|-------------|--------|------------------------|
| Source change (`src/`, `src-tauri/`, `Cargo.lock`, `patches/`, build scripts) | All 17 rebuild | Use fresh artifact |
| CI-only change (vmtest scripts, transfer scripts, report yml, tests/) | Skipped — last artifact reused | Still runs in full |
| Tag push (`v*`) | All 17 rebuild | Use fresh artifact |
| Manual override (pipeline UI) | Any job can be force-triggered | Use that artifact |

## Implementation

### 0. Content-addressed build keys

The pipeline is moving from branch-scoped artifact reuse to content-addressed
artifact reuse. Every package target computes a deterministic build key from the
tracked Git blobs, file modes, and build-affecting environment values that can
change the packaged output.

The key is produced by `scripts/ci/lib/compute-build-key.sh` and has this shape:

```text
<package-type>-<target-label>-<sha256>
```

The script intentionally uses `git ls-files -s` instead of filesystem traversal.
That hashes Git blob IDs and executable bits in a deterministic order, avoiding
accidental cache misses caused by runner-dependent `find` ordering.

Build-affecting environment values included in the hash stream include
`WEBCLIENTS_COMMIT`, `WEBCLIENTS_REF`, `RUST_VERSION`, `RUSTFLAGS`,
`CARGO_BUILD_JOBS`, `NODE_OPTIONS`, `TARGET_TRIPLE`, `DISTRO_TYPE`,
`DISTRO_PATCH`, `APPIMAGE_TARGET`, `FLATPAK_TARGET`, `SNAP_BASE`, and
`CI_RUNNER_EXECUTABLE_ARCH`.

This MR only adds the deterministic key and manifest metadata foundation. The
follow-up registry MR will use the key to download/upload package files from the
GitLab Generic Package Registry before running expensive compiles.

### 1. `changes:` rules on `.rules:build`

Defined in `.gitlab/workflows/_shared.yml`:

```yaml
.rules:build:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: &src_globs
        - src/**/*
        - src-tauri/**/*
        - patches/**/*
        - package.json
        - package-lock.json
        - Cargo.toml
        - Cargo.lock
        - scripts/build-*.sh
        - scripts/ci/lib/install-rust.sh
        - scripts/ci/lib/fetch-webclients.sh
        - .gitlab/workflows/builds.yml
        - .gitlab/workflows/_shared.yml
    - if: $CI_COMMIT_BRANCH
      changes: *src_globs
    - if: $CI_COMMIT_TAG         # release tags always rebuild
    - when: manual               # escape hatch — force any build from pipeline UI
      allow_failure: true
```

GitLab evaluates `changes:` against the MR diff (for MR pipelines) or the push
diff (for branch pipelines). If no listed file changed, the job is not
auto-started. It appears in the pipeline UI as a manual job, not hidden — this is
intentional so developers can force a rebuild without pushing a source change.

### 2. WebClients commit-pinned cache

Each build job previously cloned the entire WebClients repo (~1–2 GB) from
GitHub on every run. Now all jobs call `scripts/ci/lib/fetch-webclients.sh`,
which checks the CI cache first:

```yaml
cache:
  - key:
      files: [Cargo.lock, src-tauri/Cargo.toml]
      prefix: deb-debian12            # distro-specific prefix
    paths: [.cargo/, src-tauri/target/]
    when: always
  - key: "webclients-${WEBCLIENTS_COMMIT}"  # invalidates when WEBCLIENTS_COMMIT changes
    paths: [WebClients/]
    policy: pull-push
```

`fetch-webclients.sh` checks whether the pinned commit is already checked out in
the runner cache. Cache hit: instant. Cache miss: single `filter=blob:none`
clone at the exact `WEBCLIENTS_COMMIT` hash, no branch tracking.

### 3. Content-keyed Cargo cache

Previously each job used a static cache key (`deb-debian12-cargo`). This cached
the `target/` directory indefinitely, mixing incremental artifacts from different
dependency states. Now the key uses `key: files:` with the lockfiles:

```
key: files: [Cargo.lock, src-tauri/Cargo.toml], prefix: deb-debian12
```

The cache is automatically invalidated when `Cargo.lock` or `src-tauri/Cargo.toml`
changes (dependency update). It is reused across pipeline runs when they do not
change, making subsequent builds of the same dep graph incremental.

### 4. `optional: true` + `fetch-latest-artifact.sh` for CI-only changes

When a build job is skipped (no source change), GitLab would normally cascade-skip
all downstream jobs (`needs:` the skipped job). To prevent this, every transfer
job declares its build dependency as optional:

```yaml
transfer:debian-12:
  variables:
    BUILD_JOB_NAME: "build:deb:debian-12"
  needs:
    - job: "build:deb:debian-12"
      artifacts: true
      optional: true       # do not cascade-skip if build was skipped
```

The transfer base template then calls `fetch-latest-artifact.sh` as the first
step in `before_script`:

```yaml
.transfer:base:
  before_script:
    - apk add --no-cache bash openssh-client coreutils curl unzip
    - bash scripts/ci/lib/fetch-latest-artifact.sh "${BUILD_JOB_NAME}"
```

`fetch-latest-artifact.sh` checks whether `artifacts/` is already populated
(fresh build passed its artifacts through). If not, it calls the GitLab Jobs API:

```
GET /api/v4/projects/:id/jobs/artifacts/:ref/download?job=<job_name>
Authorization: JOB-TOKEN: $CI_JOB_TOKEN
```

This downloads a zip of the artifact directory from the last successful pipeline
for the same branch/ref, extracts it, and lets the transfer script proceed
normally with the restored artifact.

## Failure Modes

| Scenario | Behaviour |
|----------|-----------|
| Source changed, build succeeds | Normal path — fresh artifact flows through |
| Source changed, build fails | Transfer, install, vmtest are skipped (no artifact) |
| CI-only change, prior build exists on this branch | Fetch succeeds — full chain runs |
| CI-only change, no prior build on this branch | Fetch returns 404 — transfer fails with clear error |
| Tag push | `changes:` rule does not apply — all 17 builds run unconditionally |
| Manual override in UI | Developer clicks the skipped build job — it runs, produces artifact |

## Known Limitations

**1. No source-state verification on fetched artifacts.**
`fetch-latest-artifact.sh` downloads from the last successful pipeline without
checking that the artifact was built from a compatible source state. If there is
a divergence between the artifact's source and the current branch head (e.g., a
source change that failed to build), the test run will be against a stale binary.
Mitigating factor: this only applies to CI-only change commits; source change
commits always rebuild.

**2. First-build cliff on new branches.**
A new branch that has never had a successful build and receives only a CI-only
change commit will fail at the fetch step (HTTP 404). The developer must push a
source-touching commit or manually trigger the build from the pipeline UI.

**3. Docs-only commits still run transfer/install/vmtest.**
Only the build stage has `changes:` rules. Transfer, install, and vmtest always
run (they fetch the last artifact if needed). A docs-only commit will consume VM
resources running vmtest against the unchanged binary. This is conservative — it
catches regressions introduced by infrastructure changes — but can be optimised
later by adding `changes:` rules to the transfer base template if runner cost
becomes a concern.

**4. Manual-not-skipped presentation.**
When builds are skipped due to `changes:`, they appear in the pipeline UI as
yellow manual jobs, not greyed-out skipped jobs. This is the GitLab behaviour for
a rule that matches the `if:` condition but not the `changes:` condition — the
`when: manual` fallback activates. It provides a one-click force-rebuild escape
hatch but may look noisy on CI-only commits.

## Files

| File | Purpose |
|------|---------|
| `.gitlab/workflows/_shared.yml` | `.rules:build` with `changes:` and YAML anchor |
| `.gitlab/workflows/builds.yml` | All 17 build jobs — cache blocks and `fetch-webclients.sh` calls |
| `.gitlab/workflows/transfer/_base.yml` | `optional` fetch logic in `before_script` |
| `.gitlab/workflows/transfer/*.yml` | `BUILD_JOB_NAME` variable + `optional: true` per distro |
| `scripts/ci/lib/fetch-webclients.sh` | Cache-aware WebClients checkout |
| `scripts/ci/lib/fetch-latest-artifact.sh` | GitLab API artifact download for skipped builds |
