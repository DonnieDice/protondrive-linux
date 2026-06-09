# Tests

This directory contains executable test cases. Reusable CI/build helpers belong
in `scripts/` — if a file is primarily asserted by CI as a test case, it lives here.

## Layer map

| Path | What it proves | When it runs | CI stage |
|------|---------------|--------------|----------|
| `regression/` | Shell invariants: login/2FA routing, sidebar patch coverage, native sync bridge | Every MR and push | Stage 1 (GitHub Actions + GitLab gate) |
| `unit/` | Python unit tests for local helper logic | Every MR and push | Stage 1 |
| `robot/` | Robot Framework GUI and package smoke suites | Tag-gated (RC + release tags) | Stage 3/4 |
| `vm/` *(future)* | Login/2FA desktop acceptance harness against real VMs | Scheduled, not per-MR | Stage 5 |
| `src-tauri/src/*.rs` | Rust unit tests (`#[cfg(test)] mod tests`) | Every MR and push | Stage 1 |

## Key constraint

Login/2FA routing is a **desktop-only E2E concern** — the WebKit window must be live
for routing assertions to be meaningful. Do not add login or session routing tests as
container unit tests; they belong in `vm/` once the VM harness exists.

## Adding a new test

1. Decide the layer: invariant guard → `regression/`, helper logic → `unit/`, full
   GUI scenario → `robot/`, Rust module → inline in `src-tauri/src/`.
2. Make sure CI picks it up: `regression/` and `unit/` tests are collected
   automatically; `robot/` suites are tag-gated; new `vm/` suites need a scheduled job.
