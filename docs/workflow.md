# Contributing to Proton Drive Linux

Thanks for your interest in contributing! This guide covers the workflow we use for issues, branches, and merge requests. For detailed build, packaging, and development rules, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Workflow

Every meaningful change follows this five-step loop:

```
Step 1: Create Issue
  ↓
Step 2: Create Branch
  ↓
Step 3: Create Merge Request
  ↓
Step 4: MR Refinement Loop (review, iterate, fix)
  ↓
Step 5: Verify CI → Merge → Close Issue
```

## Step 1: Create Issue

Open an issue for every bug, feature request, or task. Issues:

- Track what's open/done
- Link commits and MRs back to intent (`Closes #42` auto-closes the issue on merge)
- Discuss the *why* before touching code

**Issue titles are plain text** — do NOT add `(#N)` syntax to issue titles.

## Step 2: Create Branch

One branch per issue, named to make the connection explicit:

| Prefix     | Use case                        | Example                        |
|------------|---------------------------------|--------------------------------|
| `feature/` | New functionality               | `feature/42-add-login-page`    |
| `fix/`     | Bug fixes                       | `fix/87-broken-csv-export`     |
| `chore/`   | Non-code work (docs, deps, CI)  | `chore/103-update-dependencies`|

**Never work directly on `main`.** Even for a one-line fix, create a branch and open an MR.

**No intermediate branches** (no `alpha`). All feature branches merge directly to `main`.

All development work stays strictly isolated within its branch.

## Step 3: Create Merge Request

Open a merge request (MR) when your branch is ready for review. An MR:

- Triggers CI (all build workflows run automatically)
- Lets reviewers check the diff
- Creates a record of *why* code changed
- Must be explicitly linked to the original issue
- Should have appropriate tracking tags/labels applied

### MR Title Format

```
(#PR-number) Descriptive title starting with uppercase
```

The MR title must match: `^\(#\d+\)\s[A-Z].{9,}$`

The number in the PR title is the **PR** number, not the tracked issue number.
If the PR number is not yet assigned, create the PR first, then edit the
title once the number exists.
Open an issue first when work does not already have one.

### Commit Message Format

```
(#ISSUE-number) Description starting with uppercase
```

The number in the commit title is the **issue** number, not the MR number. Example:

```bash
git commit -m "(#92) Fix flatpak YAML generation printf indentation"
```

Rules:
- Start with an uppercase letter
- Be at least 10 characters long (after the issue number prefix)
- Use `Closes #N` in the body/footer when the commit fully resolves the issue

### MR Body Format

Reference the tracked issue at the top. Use `Closes #N` when the MR fully
resolves the issue, or `Refs #N` for partial work:

```markdown
Closes #42

## Summary

- Describe the main behavior or packaging change
- Mention important files or workflow areas with plain paths

## Changed Areas

- `.github/workflows/package-workflows.yml`
- `.github/workflows/deb/debian-12/action.yml`
- `docs/packaging.md`

## Testing

- List local commands or GitHub Actions runs used to verify the change
```

Do not add handcrafted GitHub `#diff-` anchors to MR bodies. Plain repository
paths are stable, and reviewers can use the Files changed tab for exact diffs.

## Step 4: The MR Refinement Loop

Before any merge, enforce a strict code review and metadata loop:

1. **Edit Title:** Set PR title to `(#PR-number) Descriptive title`
2. **Issue Link:** Confirm the PR body includes `Closes #N` or `Refs #N`
3. **Context:** Provide a detailed summary answering **WHY** the changes were made
4. **CR Feedback:** If a code review requires changes, iterate within the same branch

### Review Bot Feedback

Before merging **any** MR, all automated review bot findings must be addressed:

- Check CodeRabbit, Qodo, and any other review bot comments on the MR
- Every actionable comment must be either **fixed** or explicitly **dismissed with justification**
- Do not merge with unresolved bot review items — even if CI passes
- If a bot comment is a false positive, dismiss it on the MR conversation so it is documented
- Re-request review after pushing fixes to ensure bots re-evaluate

## Step 5: Conditional Verification & Closure

Evaluate the automated status checks and tests.

### IF ALL CHECKERS PASS:

1. Confirm passing status
2. Close the original tracking issue
3. Merge the MR into `main`
4. Delete the remote and local branch

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

Artifacts are retained for 30 days and include the branch name for easy identification.

## CI Workflows

| Job group | Triggers on |
|-----------|-------------|
| Package builds (AppImage, Flatpak, Snap, DEB, RPM, APK, AUR) | Push to `main`, `alpha`, `feature/**`, `fix/**`, `chore/**` + tags + MRs to `main` |
| Generate package specs | Same as package builds |
| Release | Release publication and release-tag flow through `package-workflows.yml` |
| Publish AUR, Snap, Flatpak | Release events and manual dispatch through `package-workflows.yml` |

## Branch Protection

`main` is the production-ready branch with protection rules:

- Require MR before merging
- Require status checks to pass
- Require branches to be up to date before merging

## Quick Decision Guide

| Situation              | What to create                                      |
|------------------------|-----------------------------------------------------|
| Bug found              | Issue + `fix/N-description` branch + MR             |
| New feature            | Issue + `feature/N-description` branch + MR         |
| Tiny typo fix          | Branch + MR (skip the issue if truly trivial)       |
| Want to test a build   | Push to feature branch → Actions tab → download artifact |
| Ready to ship          | MR → CI passes → review → merge to main             |
