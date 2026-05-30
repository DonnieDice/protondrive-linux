---
title: "Contributing Workflow"
created: 2026-05-28
updated: 2026-05-28
type: meta
tags: [contributing, build]
sources:
  - []
---


# Contributing to Proton Drive Linux

Thanks for your interest in contributing! This guide covers the workflow we use for issues, branches, and pull requests. For detailed build, packaging, and development rules, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Workflow

Every meaningful change follows this five-step loop:

```
Step 1: Create Issue
  ↓
Step 2: Create Branch
  ↓
Step 3: Create Pull Request
  ↓
Step 4: PR Refinement Loop (review, iterate, fix)
  ↓
Step 5: Verify CI → Merge → Close Issue
```

## Step 1: Create Issue

Open an issue for every bug, feature request, or task. Issues:

- Track what's open/done
- Link commits and PRs back to intent (`Closes #42` auto-closes the issue on merge)
- Discuss the *why* before touching code

**Issue titles are plain text** — do NOT add `(#N)` syntax to issue titles.

Labels are applied automatically based on the branch prefix (see Step 2).

## Step 2: Create Branch

One branch per issue, named to make the connection explicit:

| Prefix     | Use case                        | Example                        | Auto-label     |
|------------|---------------------------------|--------------------------------|----------------|
| `feature/` | New functionality               | `feature/42-add-login-page`    | `enhancement`  |
| `fix/`     | Bug fixes                       | `fix/87-broken-csv-export`     | `bug`          |
| `chore/`   | Non-code work (docs, deps, CI)  | `chore/103-update-dependencies`| `chore`        |

**Never work directly on `main`.** Even for a one-line fix, create a branch and open a PR.

**No intermediate branches** (no `alpha`, `beta`, `staging`). All feature branches merge directly to `main`.

All development work stays strictly isolated within its branch.

### Local Verification Before Pushing

Before pushing your branch, run the local checks appropriate for your change:

- **Formatting / linting**: If a `Makefile` or `justfile` target exists (e.g. `make lint`, `just format`), run it first.
- **Build verification**: Build the component you changed if a local build target exists.
- **Unit tests**: Run `make test` or the project's test runner if one is configured.

CI will run a full suite regardless, but catching issues locally saves time.

## Step 3: Create Pull Request

Open a PR when your branch is ready for review. A PR:

- Triggers CI (all build workflows run automatically on push)
- Lets reviewers check the diff
- Creates a record of *why* code changed
- Must be explicitly linked to the original issue
- Labels are applied automatically based on the branch prefix (see Step 2)

### PR Title Format

```
(#PR-number) Descriptive title starting with uppercase
```

The PR title must match: `^\(\#\d+\)\s[A-Z].{9,}$`

The number in the PR title is the **PR** number, not the tracked issue number.
If GitHub has not assigned the PR number yet, create the PR first, then edit the
title once the number exists.
Open an issue first when work does not already have one.

### Commit Message Format

```
(#ISSUE-number) Description starting with uppercase
```

The number in the commit title is the **issue** number, not the PR number. Example:

```bash
git commit -m "(#92) Fix flatpak YAML generation printf indentation"
```

Rules:
- Start with an uppercase letter
- Be at least 10 characters long (after the issue number prefix)
- Use `Closes #N` in the body/footer when the commit fully resolves the issue

### PR Body Format

Reference the tracked issue at the top. Use `Closes #N` when the PR fully
resolves the issue, or `Refs #N` for partial work:

```markdown
Closes #42

## Summary

- Describe the main behavior or packaging change
- Mention important files or workflow areas with plain paths

## Changed Areas

- `.github/workflows/package-workflows.yml`
- `.github/workflows/deb/debian-12/action.yml`
- `docs/build-packaging/packaging.md`

## Testing

- List local commands or GitHub Actions runs used to verify the change
```

Do not add handcrafted GitHub `#diff-` anchors to PR bodies. Plain repository
paths are stable, and reviewers can use the Files changed tab for exact diffs.

## Step 4: The PR Refinement Loop

Before any merge, enforce a strict code review and metadata loop:

1. **Edit Title:** Set PR title to `(#PR-number) Descriptive title`
2. **Issue Link:** Confirm the PR body includes `Closes #N` or `Refs #N`
3. **Context:** Provide a detailed summary answering **WHY** the changes were made
4. **CR Feedback:** If a code review requires changes, iterate within the same branch

### Review Bot Feedback

Before merging **any** PR, all automated review bot findings must be addressed:

- Check CodeRabbit, Qodo, and any other review bot comments on the PR
- Every actionable comment must be either **fixed** or explicitly **dismissed with justification**
- Do not merge with unresolved bot review items — even if CI passes
- If a bot comment is a false positive, dismiss it on the PR conversation so it is documented
- Re-request review after pushing fixes to ensure bots re-evaluate

### Merge Strategy

All PRs merge to `main` using **squash merge**. This keeps the commit history
on `main` clean — one merge per PR with a single commit message. The squash
commit message should follow the PR title format:

```
(#PR-number) Descriptive title starting with uppercase
```

After the PR is merged, GitHub automatically deletes the branch (configured at
the repository level). Clean up your local copy with:

```bash
git fetch --prune
git branch -d <branch-name>
```

## Step 5: Conditional Verification & Closure

Evaluate the automated status checks and tests.

### IF ALL CHECKERS PASS:

1. Confirm passing status
2. Close the original tracking issue
3. Merge the PR into `main` (squash merge)
4. Clean up: remote branch is deleted automatically; delete the local branch

### IF ANY CHECKER FAILS:

1. Reject progression
2. Loop back to **Step 4** for fixes and code iteration

## Testing Builds on Feature Branches

The visible GitHub Actions entrypoint is
`.github/workflows/package-workflows.yml`. It calls package-specific
implementations from subfolders such as `.github/workflows/deb/debian-12/` and
`.github/workflows/rpm/fedora-43/`.

Package jobs trigger on pushes to `feature/**`, `fix/**`, and `chore/**`
branches. To test a build:

1. Push your branch
2. Go to the **Actions** tab on GitHub
3. Find the workflow run for your push
4. Download the build artifact from the run summary

Artifacts are retained for 30 days and include the branch name for easy
identification.

Job triggers for PRs to `main` follow the same rules — every push to an open PR
kicks off the package workflows.

## CI Workflows

| Job group | Triggers on |
|-----------|-------------|
| Package builds (AppImage, Flatpak, Snap, DEB, RPM, APK, AUR) | Push to `main`, `feature/**`, `fix/**`, `chore/**` + tags + PRs to `main` |
| Generate package specs | Same as package builds |
| Release | Release publication and release-tag flow through `package-workflows.yml` |
| Publish AUR, Snap, Flatpak | Release events and manual dispatch through `package-workflows.yml` |

### CI Systems

This project uses **two CI systems** that mirror each other:

| System | Entrypoint | Purpose |
|--------|-----------|---------|
| **GitHub Actions** | `.github/workflows/package-workflows.yml` | Primary CI — build, package, release on GitHub |
| **GitLab CI** | `.gitlab-ci.yml` (in repo root) | Mirror — same package builds on GitLab infrastructure |

Both systems run the same build logic against the same branch patterns. The
GitLab pipeline mirrors the GitHub Actions workflow for redundancy. Status
on either system is sufficient to block or unblock a merge.

### Troubleshooting CI Failures

If CI fails:

1. Check the **Actions** tab (GitHub) or **CI/CD > Pipelines** (GitLab) for the failed run
2. Click on the failed job to see the build log
3. Common failure modes:
   - **Network timeout** — retry the job (GitHub: rerun from Actions tab; GitLab: click the retry icon)
   - **Missing artifact** — ensure your branch is up to date with `main`; rebase if stale
   - **Build error** — check the compile output; verify locally with `make` or the project's build command

If the failure is a known intermittent issue, note it in the PR and retry. If CI
passes on a subsequent retry without code changes, leave a comment documenting
the transient failure.

## Branch Protection

`main` is the production-ready branch with protection rules:

- Require PR before merging
- Require status checks to pass
- Require branches to be up to date before merging
- Automatically delete head branches after merge

## Quick Decision Guide

| Situation              | What to create                                      |
|------------------------|-----------------------------------------------------|
| Bug found              | Issue + `fix/N-description` branch + PR             |
| New feature            | Issue + `feature/N-description` branch + PR         |
| Tiny typo fix          | Branch + PR (skip the issue if truly trivial)       |
| Want to test a build   | Push to feature branch → Actions tab → download artifact |
| Ready to ship          | PR → CI passes → review → squash merge to main      |
