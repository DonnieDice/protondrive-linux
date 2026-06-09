# Release Process

This document captures the tag-only release flow with an RC gate.

## Steps

1. **Land all changes to `main` via MR** — all CI gates must be green before merging.

2. **Bump version in all four sources** — `test:version-consistency` enforces they match:
   - `package.json`
   - `package-lock.json` (updated automatically by `npm install`)
   - `src-tauri/tauri.conf.json`
   - `src-tauri/Cargo.toml` (and `Cargo.lock` via `cargo build`)

3. **Tag `vX.Y.Z-rc.1`** — triggers the full build matrix, signing, SBOM, and
   provenance generation. Package smoke tests run. **No publish jobs execute on RC tags.**

4. **Validate the RC** — install-smoke the package artifacts on representative targets,
   run manual checks. Open a fix MR and re-tag if anything fails.

5. **Tag `vX.Y.Z`** — runs the same validated pipeline. Publish jobs become available
   as manual, approval-gated steps. The release artifact is the one built from the tag,
   never rebuilt from source.

6. **Trigger publish jobs** — each publish job verifies checksums and signatures before
   promoting artifacts to the target store (AUR, Flathub, Snap, package repositories).

## Notes

- Never push directly to `main`. All version bumps go through MR → merge → tag.
- `test:version-consistency` in CI will fail the pipeline if the four version sources
  disagree. Run `just versions` locally to catch this before pushing.
- `docs/release-checklist.md` has the per-target publish checklist (secrets, smoke
  status, blocked targets). Keep that file updated alongside this process doc.
- If something goes wrong after publishing, follow `docs/ci-cd/rollback-process.md`
  for per-store rollback steps and the hotfix branch flow.
- The RC stage exists to catch packaging regressions before they reach users. At least
  one install-smoke pass on a real machine is required before promoting to a final tag.
