---
description: Project conventions for protondrive-linux — commit messages, PR titles, PR body format, branching, and version bumps. Load before every task.
mode: primary
---

# ProtonDrive Linux Project Conventions

## Repository

- Repo: `donniedice/protondrive-linux`
- Default branch: `main`
- **Never push directly to `main`** — always use Issue → Branch → PR → Merge

## Commit Messages

- Format: `(#N) Description` where N is the **issue** number
- Start with uppercase letter
- At least 10 characters after the issue prefix
- Regex: `^\(#\d+\)\s[A-Z].{9,}$`
- Use `Closes #N` or `Refs #N` in commit body/footer for traceability
- The number in the commit title is the **issue** number, not the PR number

## PR Titles

- Format: `(#PR-number) Descriptive title starting with uppercase`
- The number in the PR title is the **PR** number (assigned by GitHub after creation)
- Edit the title after GitHub assigns the PR number
- Same regex as commits: `^\(#\d+\)\s[A-Z].{9,}$`

## PR Body Format

Reference the issue at the top, then list each changed file with a GitHub
diff anchor so reviewers can jump directly to that file's diff in the PR:

```markdown
Issue: #42

## Changes

### [`README.md`](https://github.com/DonnieDice/protondrive-linux/pull/47/files#diff-abc123) — description of changes
- Bullet list of what changed in this file

### [`docs/packaging.md`](https://github.com/DonnieDice/protondrive-linux/pull/47/files#diff-def456) — description of changes
- Bullet list of what changed in this file
```

The `#diff-` anchor is the file's SHA from the PR files API. To get the
real SHAs before editing the PR body:

```bash
gh api repos/DonnieDice/protondrive-linux/pulls/NUMBER/files \
  --jq '.[] | .filename + " " + .sha'
```

Do **not** fabricate or guess the diff hashes — always fetch them from the
API. Each link follows the pattern:

```
https://github.com/DonnieDice/protondrive-linux/pull/NUMBER/files#diff-{SHA}
```

## Branch Naming

| Prefix | Use case | Example |
|--------|----------|---------|
| `feature/` | New functionality | `feature/42-add-login-page` |
| `fix/` | Bug fixes | `fix/87-broken-csv-export` |
| `chore/` | Non-code work (docs, deps, CI) | `chore/103-update-dependencies` |

Always clean up remote branches after merge.

## Version Bumps

When merging meaningful changes, bump the version in ALL THREE files:
- `package.json`
- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`

## CI Workflows

- 17 build/spec workflows trigger on `push` to `main`, `alpha`, `feature/**`, `fix/**`, `chore/**` + tags + PRs to `main`
- `release.yml` and `publish-aur.yml` are main/tags-only — do NOT add feature branch triggers
- CommitCheck false positives can be ignored when the message follows `(#N) Description` correctly

## Packaging State

- Alpine 3.23 has a workflow (`build-apk.alpine.3.23.yml`) but is still `roadmap-patch-ready` — not release-gated yet
- `compatibility-map.yml` must stay in sync with actual workflows and `docs/packaging.md`
- AUR package is `proton-drive` (native build), not `proton-drive-bin` (old wrapper, replaced in v1.4.0)

## Key Docs

- `CONTRIBUTING.md` — root workflow guide (branches, commits, PRs)
- `docs/CONTRIBUTING.md` — detailed build, packaging, development rules
- `docs/packaging.md` — canonical human-readable packaging policy
- `packaging/compatibility-map.yml` — machine-readable target metadata
- `docs/CHANGELOG.md` — release history
- `docs/release-checklist.md` — pre-release checklist
- `docs/new-build-checklist.md` — adding new package targets
