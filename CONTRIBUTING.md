# Contributing to Proton Drive Linux

Thanks for your interest in contributing! This guide covers the workflow we use for issues, branches, and pull requests. For detailed build, packaging, and development rules, see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Workflow

Every meaningful change follows this loop:

```
Open Issue → Create Branch → Push Commits → Open PR → CI Runs → Review → Merge → Issue Auto-Closes
```

## Issues

Open an issue for every bug, feature request, or task. Issues:

- Track what's open/done
- Link commits and PRs back to intent (`Closes #42` auto-closes the issue on merge)
- Discuss the *why* before touching code

## Branch Naming Convention

One branch per issue, named to make the connection explicit:

| Prefix     | Use case                        | Example                        |
|------------|---------------------------------|--------------------------------|
| `feature/` | New functionality               | `feature/42-add-login-page`    |
| `fix/`     | Bug fixes                       | `fix/87-broken-csv-export`     |
| `chore/`   | Non-code work (docs, deps, CI)  | `chore/103-update-dependencies`|

**Never work directly on `main`.** Even for a one-line fix, create a branch and open a PR.

## Commit Messages

Use the issue number at the front of the title:

```bash
git commit -m "(#123) Add system tray icon support"
```

Rules:
- The number in the commit title is the **issue** number (e.g., `#123`), not
  the PR number
- Start with an uppercase letter
- Be at least 10 characters long (after the issue number prefix)
- Put the issue number prefix at the start: `(#42) Title here`
- Use `Closes #123` in the body/footer when the commit fully resolves the issue

## Pull Requests

Open a PR when your branch is ready for review. PR title format:

```
(#PR-number) Descriptive title starting with uppercase
```

The PR title must match: `^\(#\d+\)\s[A-Z].{9,}$`

The number in the PR title is the **PR** number (assigned by GitHub after you
open the PR), not the issue number. Edit the title after GitHub assigns the PR
number — it appears in the URL and page header immediately. A PR:

- Triggers CI (all build workflows run automatically)
- Lets reviewers check the diff
- Creates a record of *why* code changed

### PR Body Format

Reference the issue at the top, then list each changed file with a GitHub
permalink so reviewers can jump directly to the source. Each changed file gets
its own line with a link and a brief summary:

```markdown
Issue: #42

## Changes

### [`README.md`](https://github.com/DonnieDice/protondrive-linux/blob/<branch>/README.md) — description of changes
- Bullet list of what changed in this file

### [`docs/packaging.md`](https://github.com/DonnieDice/protondrive-linux/blob/<branch>/docs/packaging.md) — description of changes
- Bullet list of what changed in this file
```

Replace `<branch>` with your feature branch name. After the PR is merged the
links will resolve to `main`, but during review they point to the exact branch.

## Testing Builds on Feature Branches

All build workflows trigger on pushes to `feature/**`, `fix/**`, and `chore/**` branches. To test a build:

1. Push your branch
2. Go to the **Actions** tab on GitHub
3. Find the workflow run for your push
4. Download the build artifact from the run summary

Artifacts are retained for 30 days and include the branch name for easy identification.

## CI Workflows

| Workflow | Triggers on |
|----------|-------------|
| Build workflows (AppImage, Flatpak, Snap, DEB, RPM, APK, AUR) | Push to `main`, `alpha`, `feature/**`, `fix/**`, `chore/**` + tags + PRs to `main` |
| Generate Package Specs | Same as build workflows |
| Release | Push to `main` + tags only |
| Publish AUR | Release events only |

## Branch Protection

`main` is the production-ready branch with protection rules:

- Require PR before merging
- Require status checks to pass
- Require branches to be up to date before merging

## Quick Decision Guide

| Situation              | What to create                                      |
|------------------------|-----------------------------------------------------|
| Bug found              | Issue + `fix/N-description` branch + PR             |
| New feature            | Issue + `feature/N-description` branch + PR         |
| Tiny typo fix          | Branch + PR (skip the issue if truly trivial)       |
| Want to test a build   | Push to feature branch → Actions tab → download artifact |
| Ready to ship          | PR → CI passes → review → merge to main             |
