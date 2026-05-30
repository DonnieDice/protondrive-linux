---
title: "Wiki Log"
created: 2026-05-28
updated: 2026-05-28
type: meta
tags: [schema, conventions]
sources: []
---

# Wiki Log

Chronological record of all structural changes to the `docs/` wiki.

## 2026-05-28

### Frontmatter rollout (Hermes)
- **Added** YAML frontmatter to 33 documents (all except SCHEMA.md which was created with it)
- **Schema:** type, tags, sources, created, updated fields per SCHEMA.md taxonomy
- **Types assigned:** 4 architecture, 9 module, 9 guide, 2 runbook, 5 meta, 2 index, 1 reference, 1 utility
- **Tags:** 18-tag controlled vocabulary covering sync, auth, sso, proxy, webview, build, ci, packaging, database, navigation, download, storage, configuration, contributing, security, release, troubleshooting, schema

### Cross-reference expansion (Hermes)
- **Added** `## See Also` sections to 11 technical docs (ARCHITECTURE, sync-system, live-sync-module, sync-database, sync-db-module, auth-module, sso-authentication, proxy-system, proton-navigation, webview-integration, blob-downloads, build-packaging)
- **Format:** Bullet list with bold title, em-dash, one-line purpose summary

### Troubleshooting sections (Hermes)
- **Added** `## Troubleshooting` to 6 docs: sync-system (3 issues), live-sync-module (4 issues), sync-database (3 issues), auth-module (3 issues), sso-authentication (3 issues), proxy-system (3 issues), webview-integration (4 issues)
- **Format:** Symptoms, Causes, Fix with shell commands for each issue

### New documents created (Hermes)
- **`configuration-reference.md`** — Centralized reference: all compile-time constants, env vars, timeouts, file paths, API endpoints, Cargo features
- **`url-log-webview-storage.md`** — Documented `url_log.rs` and `webview_storage.rs` utility modules
- **`SCHEMA.md`** — Wiki domain, conventions, type system, tag taxonomy, frontmatter spec
- **`README.md`** — Reorganized into categorized sections (Architecture, Sync, Build/Packaging, Config/Utilities, Development, Debugging)

### README reorganization (Hermes)
- **Replaced** flat link list with categorized groups
- **Added** descriptions for every document link
- **Added** new docs to inventory (ARCHITECTURE.md, webview-integration, proton-navigation, live-sync-module, sync-db-module, configuration-reference, url-log-webview-storage)

## Pre-Wiki History

### 2026-05-06 – 2026-05-27
- Initial documentation generation (kanban workers)
- Initial codebase audit and architecture docs
- Sync system docs written (sync-system, sync-database, live-sync-module)
- Auth and SSO docs written
- Build system and CI docs written
- Multiple fix passes: CSP, line numbers, code snippet accuracy, cookie handling, schema version

### 2025-11-29 – 2025-12-29
- Original project docs: CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, workflow.md
- Worker login SRI debugging doc
