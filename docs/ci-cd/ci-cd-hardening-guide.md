# CI/CD Hardening Guide

This guide captures the current hardening plan for `protondrive-linux` as it
exists now: a monolithic `.gitlab-ci.yml`, the included
`.gitlab-ci-vm-tests.yml`, and GitHub Actions used as a public mirror/manual
workflow surface.

## Current Shape

GitLab is authoritative for package builds, release creation, and publishing.
GitHub is a mirror for public PR/issue activity and manual package workflow
dispatch.

Current GitLab stages:

```text
detect -> audit -> update -> lint -> test -> security -> build -> spec -> release -> publish
```

The first three stages are for the AI documentation audit path. The `lint`,
`test`, and `security` stages are pre-build hardening gates. The release factory
starts at `build`.

## Corrections To Older Reviews

- This repo does not currently use split `.gitlab/workflows/*.yml` includes.
  Implementations must patch the current `.gitlab-ci.yml`.
- There is no first-party JavaScript or TypeScript app code to lint. The UI is
  Proton WebClients, fetched and built by CI. Gate first-party Rust, shell,
  Python, YAML, and workflow logic instead.
- The project license is AGPL-3.0, so AGPL/GPL-compatible dependencies are not
  inherently disallowed. Unknown, proprietary, or incompatible licenses are the
  risk.
- GitLab workflow rules currently prevent ordinary branch/MR full release
  pipelines. `.rules:release` still had a stale `main` push condition, so release
  rules should remain tag-only for clarity and future safety.
- GitHub `package-workflows.yml` had dead `pull_request_target`/`issues`
  triggers with broad workflow-level write permissions. Keep it manual and
  least-privilege unless GitHub is deliberately promoted to release authority.

## Phase 1 Controls

Implemented controls:

- `lint:shell` with ShellCheck.
- `lint:yaml` with yamllint.
- `lint:actions` with actionlint.
- `lint:python` with Ruff.
- `test:python-scripts` with Python AST parse smoke checks.
- `test:version-consistency` across `package.json`, `package-lock.json`,
  `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, and
  `src-tauri/tauri.conf.json`.
- `security:secrets` with gitleaks.
- `security:cargo-deny` with an AGPL-correct `deny.toml`, advisory at first.
- `security:npm-audit`, advisory at first.

## Governance Controls

Implemented controls:

- `.rules:release` is tag-only.
- GitHub `package-workflows.yml` is manual-only.
- GitHub `package-workflows.yml` defaults to `contents: read`; jobs that need
  publish/release write permissions should elevate locally.

Still recommended:

- Protected GitLab `v*` tags.
- Protected/masked/hidden publishing variables.
- Protected publish environments requiring approval.
- Separate runner trust classes for MR gates, release builds, and publishing.
- SBOM/signing/provenance on tag pipelines.
- Release upload TLS verification through a trusted internal CA instead of any
  TLS bypass.
