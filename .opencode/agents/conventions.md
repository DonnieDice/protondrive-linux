---
description: Project conventions for protondrive-linux repo — commit messages, PR titles, workflow patterns.
mode: all
---

# Proton Drive Linux — Project Conventions

## Commit Messages

Commit messages must match CommitCheck regex. The format is:

```
(#ISSUE_NUMBER) Description
```

- The issue number goes at the **START** of the commit title, in parentheses
- Description starts with an uppercase letter and is at least 10 characters
- Example: `(#42) Fix workflow YAML generation printf indentation`
- Use `Closes #N` in the body/footer when the commit resolves the issue
- Use `Refs #N` when the commit references but doesn't close an issue

## PR Titles

PR titles use the PR number at the **START**:

```
(#PR_NUMBER) Description
```

- Example: `(#93) Fix flatpak YAML generation printf indentation`
- Must match `^\(#\d+\)\s[A-Z].{9,}$`
- The PR number is assigned by GitHub after you create the PR — edit the title immediately

## NEVER confuse these two

| Context | Format | Example |
|---------|--------|---------|
| Commit message | `(#ISSUE) Description` | `(#92) Fix workflow YAML indentation` |
| PR title | `(#PR) Description` | `(#93) Fix workflow YAML indentation` |

## Build Workflow Patterns

- Every build workflow must have `rm -rf src-tauri/target/release/bundle/<type>` before the build step to prevent stale cached artifacts
- Every build workflow must use `WEBCLIENTS_REF: main` env var (not hardcoded `--branch main`) for reproducible builds
- Alpine APK workflows also need `git config --global --add safe.directory "$GITHUB_WORKSPACE"` after creating `.cargo/config.toml`
- `scripts/build-webclients.sh` respects `WEBCLIENTS_REF` env var with `main` as default

## Branch Naming

| Prefix | Use case | Example |
|--------|----------|---------|
| `feature/` | New functionality | `feature/42-add-login-page` |
| `fix/` | Bug fixes | `fix/87-broken-csv-export` |
| `chore/` | Non-code work (docs, deps, CI) | `chore/103-update-dependencies` |

No intermediate branches (no `alpha`). All feature branches merge directly to `main`.

## Before Creating Any PR

1. Always `git fetch origin` and `git pull origin main` to get latest base
2. Create feature branch from latest main
3. Make changes, commit with `(#ISSUE) Description` format
4. Push branch, create PR with `(#PR) Description` title format
5. Edit PR body with issue reference and real diff SHA links for each changed file
6. Wait for CI and review bot feedback before merging
7. After merge, delete both remote and local branches
