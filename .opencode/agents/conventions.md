---
description: Project conventions for protondrive-linux repo - commit messages, PR titles, issue/PR body format, and workflow patterns.
mode: all
---

# ProtonDrive Linux Project Conventions

## Commit Messages

Commit messages must match CommitCheck regex:

```text
(#ISSUE_NUMBER) Description
```

- The issue number goes at the start of the commit title, in parentheses.
- Description starts with an uppercase letter and is at least 10 characters.
- Example: `(#42) Fix workflow YAML generation printf indentation`.
- Use `Closes #N` in the body/footer when the commit resolves the issue.
- Use `Refs #N` when the commit references but does not close an issue.

## PR Titles

PR titles use the PR number at the start:

```text
(#PR_NUMBER) Description
```

- Example: `(#93) Fix flatpak YAML generation printf indentation`.
- Must match `^\(#\d+\)\s[A-Z].{9,}$`.
- The PR title number is the PR number, not the tracked issue number.
- If the PR number is not known yet, create the PR first, then edit the title
  once GitHub assigns the PR number.
- If there is no tracking issue, create or verify one before opening the PR.

## Issue And PR Links

Numbers and links are required, but they must be stable and real.

| Context | Required reference | Example |
|---------|--------------------|---------|
| Commit message | Issue number | `(#92) Fix workflow YAML indentation` |
| PR title | PR number | `(#93) Fix workflow YAML indentation` |
| PR body | Closing issue plus icon links | `Closes #92` and `- 🔗 Related: #91` |
| Issue body | Related issue/PR URLs when known | `https://github.com/DonnieDice/protondrive-linux/pull/99` |

Do not use guessed GitHub `#diff-...` anchors. Use plain repository file paths
for changed files, and link to the PR or Actions run when the whole PR/run is
the thing being referenced.

Do not add a `Tracking issue` line inside the issue that is already being
tracked. For example, issue `#98` must not contain `Tracking issue: #98` or a
link to itself as its own tracking issue. That wording is only useful from a PR,
another issue, or external documentation.

## Agent Issue Body Format

This is for agent-created or agent-edited issues. User-facing issue forms under
`.github/ISSUE_TEMPLATE/` are separate.

Always write issue bodies as multi-line Markdown. Never submit one collapsed
paragraph. Never escape file paths with backslashes.

Use this shape for technical issues:

```markdown
## Problem

- Describe the broken behavior.
- Include real related links, for example:
  - https://github.com/DonnieDice/protondrive-linux/pull/99
  - https://github.com/DonnieDice/protondrive-linux/issues/98

Do not include the current issue's own URL as a `Tracking issue` reference.

## Affected Files

- `src-tauri/src/main.rs`
- `src-tauri/Cargo.toml`

## Cause

Explain the likely cause.

## Fix

- Concrete fix item
- Concrete validation item
```

## PR Body Format

Use this shape:

```markdown
Closes #92

## Links

- 🔗 Related: #91
- 🧾 Run: https://github.com/DonnieDice/protondrive-linux/actions/runs/123456789

## Summary

- What changed.
- Why it changed.

## Changed Areas

- `.github/workflows/package-workflows.yml`
- `docs/workflow.md`

## Testing

- `git diff --check`
```

Do not use generic PR-body headers like `Issue: #92`, `Related PR: #91`, or
`PR: #93`. Keep `Closes #N` as the tracked issue reference, do not link the
current PR inside its own body, and only add related links that provide extra
context.

## Build Workflow Patterns

- The visible workflow entrypoint is `.github/workflows/package-workflows.yml`.
- Package-specific implementations live under `.github/workflows/<package>/<target>/action.yml`.
- Remote GitHub Actions builds run on Linux runners.
- `scripts/build-webclients.sh` respects `WEBCLIENTS_REF` with `main` as default.

## Branch Naming

| Prefix | Use case | Example |
|--------|----------|---------|
| `feature/` | New functionality | `feature/42-add-login-page` |
| `fix/` | Bug fixes | `fix/87-broken-csv-export` |
| `chore/` | Non-code work, docs, deps, CI | `chore/103-update-dependencies` |

No intermediate branches. All feature branches merge directly to `main`.

## Before Creating Any PR

1. Fetch the latest base.
2. Create a feature/fix/chore branch from latest `main`.
3. Make changes and commit with `(#ISSUE) Description`.
4. Push branch, create PR, then edit the title to `(#PR) Description`.
5. Edit PR body with issue links, PR link, changed paths, and testing.
6. Wait for CI and review bot feedback before merging.
7. After merge, delete both remote and local branches.
