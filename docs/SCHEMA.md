---
title: Schema
created: 2026-05-28
updated: 2026-05-28
type: meta
tags: [schema, conventions]
---

# SCHEMA.md — ProtonDrive Linux Wiki

## Domain

The **protondrive-linux** knowledge base documents the Proton Drive native Linux
desktop client: its architecture, modules, build system, CI pipeline, sync engine,
authentication flow, and operational procedures.

- **Repository:** donniedice/protondrive-linux (GitLab primary, GitHub mirror)
- **Language:** Rust (Tauri backend) + TypeScript/React (SPA, from Proton)
- **License:** AGPL-3.0
- **Root path:** `docs/` in the repository
- **Source anchor:** `src-tauri/src/`

## Types

Every document must declare a `type` in its YAML frontmatter. Valid types:

| Type | Purpose | Example |
|---|---|---|
| `architecture` | System design, component overview, data flow | ARCHITECTURE.md |
| `module` | Code module documentation — maps to a `.rs` file | live-sync-module.md |
| `reference` | Centralized reference: config, API, constants | configuration-reference.md |
| `guide` | Procedural how-to: build, release, contribute | new-build-checklist.md |
| `runbook` | Operational troubleshooting and regression testing | login-sync-regression-runbook.md |
| `meta` | Project governance, security, contributing | CONTRIBUTING.md |
| `index` | Landing page or doc inventory | index.md, README.md |
| `utility` | Small utility module documentation | url-log-webview-storage.md |

## Tags

Controlled taxonomy. Tags describe what subsystem or concern a document covers.

| Tag | Scope |
|---|---|
| `architecture` | System design, component layout, data flow |
| `sync` | File synchronization: watcher, poller, events, suppression cache |
| `auth` | Authentication, session lifecycle, cookie management |
| `sso` | Single sign-on: CAPTCHA, redirects, token extraction |
| `proxy` | HTTP/XHR proxy layer: request interception, URL rewriting |
| `webview` | WebKitGTK integration: rendering, IPC, storage |
| `build` | Build system: Cargo, DISTRO_TYPE, feature flags |
| `ci` | CI pipeline: GitLab CI, jobs, artifacts |
| `packaging` | Distribution packaging: AppImage, DEB, RPM, AUR, Snap |
| `database` | SQLite sync metadata database: schema, migrations |
| `navigation` | URL rewriting, domain routing, CAPTCHA lifecycle |
| `download` | Blob download pipeline: interception, save to disk |
| `storage` | Persistent storage: WebView data dir, cookies |
| `configuration` | Compile-time constants, env vars, timeouts |
| `contributing` | Development setup, PR workflow |
| `security` | Security policy, vulnerability reporting |
| `release` | Release process, versioning, artifact naming |
| `troubleshooting` | Common issues, symptoms, fixes |

## Frontmatter Conventions

Every `.md` file in `docs/` must open with YAML frontmatter between `---`
delimiters. Required fields:

```yaml
---
title: Human-readable page title
created: 2026-05-28
updated: 2026-05-28
type: module
tags: [sync, architecture]
sources:
  - src-tauri/src/live_sync.rs
  - src-tauri/src/main.rs
---
```

- **title** — Display title. Should match the `# Heading` or be a concise label.
- **created** — ISO 8601 date (YYYY-MM-DD). Original creation or first wiki entry.
- **updated** — ISO 8601 date. Update on every substantive edit.
- **type** — One of the controlled types above.
- **tags** — YAML list. At least one tag from the taxonomy.
- **sources** — YAML list of source files the doc maps to. Use paths relative to repo root.

Optional:
- **redirect_from** — YAML list of old paths that redirect here.
- **deprecated** — Boolean. Set `true` if superseded by another doc.

## Cross-Reference Conventions

Two link styles are acceptable:

1. **Markdown links** (preferred for build-time static site generation):
   ```markdown
   [Live Sync Module](live-sync-module.md)
   ```

2. **WikiLinks** (preferred for knowledge-base tools that resolve them):
   ```markdown
   [[live-sync-module|Live Sync Module]]
   ```

Use descriptive link text that includes the document title and a one-line
purpose summary, e.g.:
> **[Live Sync Module](live-sync-module.md)** — Core engine: watcher/poller threads, suppression cache, event contract

## Index Structure

- **[index.md](index.md)** — VitePress landing page (hero, features grid)
- **[README.md](README.md)** — Categorized doc inventory with one-line descriptions
- **[about.md](about.md)** — End-user project overview (features, constraints, disclaimer)

## Update Log

- **[log.md](log.md)** — Chronological log of all wiki edits: creation, restructuring, content updates. Each entry records date, author, files changed, and a one-line summary.

## Maintenance

- When a new source module is added to `src-tauri/src/`, create a corresponding
  `*module*.md` doc and add it to README.md.
- When a compile-time constant changes in the source, update
  `configuration-reference.md`.
- When troubleshooting discovers a new issue, add it to the relevant module's
  Troubleshooting section.
- Run `git diff --stat` before committing to ensure only intended files changed.
