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

## Step 2: Create Branch

One branch per issue, named to make the connection explicit:

| Prefix     | Use case                        | Example                        |
|------------|---------------------------------|--------------------------------|
| `feature/` | New functionality               | `feature/42-add-login-page`    |
| `fix/`     | Bug fixes                       | `fix/87-broken-csv-export`     |
| `chore/`   | Non-code work (docs, deps, CI)  | `chore/103-update-dependencies`|

**Never work directly on `main`.** Even for a one-line fix, create a branch and open a PR.

**No intermediate branches** (no `alpha`). All feature branches merge directly to `main`.

All development work stays strictly isolated within its branch.

## Step 3: Create Pull Request

Open a PR when your branch is ready for review. A PR:

- Triggers CI (all build workflows run automatically)
- Lets reviewers check the diff
- Creates a record of *why* code changed
- Must be explicitly linked to the original issue
- Should have appropriate tracking tags/labels applied

### PR Title Format

```
(#PR-number) Descriptive title starting with uppercase
```

The PR title must match: `^\(#\d+\)\s[A-Z].{9,}$`

The number in the PR title is the **PR** number (assigned by GitHub after you open the PR), not the issue number. Edit the title after GitHub assigns the PR number — it appears in the URL and page header immediately.

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

Reference the issue at the top, then list each changed file with a GitHub diff anchor so reviewers can jump directly to that file's diff in the PR:

```markdown
Issue: #42

## Changes

### [`README.md`](https://github.com/DonnieDice/protondrive-linux/pull/47/files#diff-abc123) — description of changes
- Bullet list of what changed in this file

### [`docs/packaging.md`](https://github.com/DonnieDice/protondrive-linux/pull/47/files#diff-def456) — description of changes
- Bullet list of what changed in this file
```

The `#diff-` anchor is the file's SHA from the PR files API. To get the real SHAs before editing the PR body:

```bash
gh api repos/DonnieDice/protondrive-linux/pulls/NUMBER/files \
  --jq '.[] | .filename + " " + .sha'
```

Do **not** fabricate or guess the diff hashes — always fetch them from the API. Each link follows the pattern:

```text
https://github.com/DonnieDice/protondrive-linux/pull/NUMBER/files#diff-{SHA}
```

## Step 4: The PR Refinement Loop

Before any merge, enforce a strict code review and metadata loop:

1. **Edit Title:** Set PR title to `(#PR-number) Descriptive title`
2. **File Links:** Include direct diff links to each changed file using real SHAs from the GitHub API
3. **Context:** Provide a detailed summary answering **WHY** the changes were made
4. **CR Feedback:** If a code review requires changes, iterate within the same branch

### Review Bot Feedback

Before merging **any** PR, all automated review bot findings must be addressed:

- Check CodeRabbit, Qodo, and any other review bot comments on the PR
- Every actionable comment must be either **fixed** or explicitly **dismissed with justification**
- Do not merge with unresolved bot review items — even if CI passes
- If a bot comment is a false positive, dismiss it on the PR conversation so it is documented
- Re-request review after pushing fixes to ensure bots re-evaluate

## Step 5: Conditional Verification & Closure

Evaluate the automated status checks and tests.

### IF ALL CHECKERS PASS:

1. Confirm passing status
2. Close the original tracking issue
3. Merge the PR into `main`
4. Delete the remote and local branch

### IF ANY CHECKER FAILS:

1. Reject progression
2. Loop back to **Step 4** for fixes and code iteration

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
| Build workflows (AppImage, Flatpak, Snap, DEB, RPM, APK, AUR) | Push to `main`, `feature/**`, `fix/**`, `chore/**` + tags + PRs to `main` |
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
