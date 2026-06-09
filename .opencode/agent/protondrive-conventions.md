---
description: Project conventions for protondrive-linux - commit messages, PR titles, issue/PR body format, branching, and version bumps. Load before every task.
mode: primary
---

# ProtonDrive Linux Project Conventions

## Repository

- Repo: `DonnieDice/protondrive-linux`
- Default branch: `main`
- **Never push directly to `main`** - always use Issue -> Branch -> PR -> Merge.
- No intermediate branches. Feature branches merge directly to `main`.

## Workflow Execution Protocol

### Step 1: Create Issue

- Prompt or verify the creation of a tracking issue.
- Issue titles are plain text. Do **not** add `(#N)` syntax to issue titles.
- Agent-created issue bodies must be valid multi-line Markdown, not one collapsed paragraph.
- Agent-created issue bodies must include real issue/PR numbers and links when known.
- Do **not** add a `Tracking issue` link inside the issue being tracked. An
  issue page already identifies itself; self-links are redundant and confusing.

### Step 2: Create Branch

- Create a tracking branch from the issue.
- Branch naming must be explicit so team members instantly understand its purpose.
- All development work stays strictly isolated within this branch.

| Prefix | Use case | Example |
|--------|----------|---------|
| `feature/` | New functionality | `feature/42-add-login-page` |
| `fix/` | Bug fixes | `fix/87-broken-csv-export` |
| `chore/` | Non-code work, docs, deps, CI | `chore/103-update-dependencies` |

### Step 3: Create Pull Request

- Initialize the PR from the working branch.
- Explicitly link the PR to the original issue.
- Apply appropriate tracking tags and labels to the PR.

### Step 4: The PR Refinement Loop

Enforce a strict code review and metadata loop before any merge:

1. **Edit Title:** Set PR title to `(#PR-number) Descriptive title`.
2. **Links:** Include useful related links in a `## Links` section using
   compact icon bullets.
3. **Changed Areas:** Use plain repository file paths for changed files.
4. **Context:** Provide a detailed summary answering why the changes were made.
5. **CR Feedback:** If review requires changes, iterate within the same branch.

### Step 5: Conditional Verification and Closure

- **IF ALL CHECKERS PASS:** Confirm status, close the original issue, merge the PR into `main`.
- **IF ANY CHECKER FAILS:** Reject progression, loop back to Step 4.

## Commit Messages

- Format: `(#N) Description` where N is the **issue** number.
- Start with uppercase letter.
- At least 10 characters after the issue prefix.
- Regex: `^\(#\d+\)\s[A-Z].{9,}$`.
- Use `Closes #N` or `Refs #N` in commit body/footer for traceability.
- The number in the commit title is the **issue** number, not the PR number.

## PR Titles

- Format: `(#PR-number) Descriptive title starting with uppercase`.
- The number in the PR title is the **PR** number, not the tracked issue number.
- If the PR number is not known yet, create the PR first, then edit the title
  once GitHub assigns the PR number.
- Keep the tracked issue in the PR body with `Closes #N` or `Refs #N`.
- Same regex as commits: `^\(#\d+\)\s[A-Z].{9,}$`.
- Use tracking issue wording in PR bodies or external docs only, never as a
  self-reference inside the tracked issue body.

## Agent Issue Body Format

This is for agent-created or agent-edited GitHub issues. It is separate from the
user-facing `.github/ISSUE_TEMPLATE/*.yml` forms.

Always write issue bodies as multi-line Markdown. Never submit a body as one
long line. Never escape file paths with backslashes like `\src-tauri/main.rs\`.

Use this shape when filing technical issues:

```markdown
## Problem

Describe the broken behavior, including real issue/PR links when relevant:

- Related PR: https://github.com/DonnieDice/protondrive-linux/pull/97
- Related issue: https://github.com/DonnieDice/protondrive-linux/issues/98

## Affected Files

- `src-tauri/src/main.rs`
- `src-tauri/Cargo.toml`

## Cause

Explain the likely cause. Keep links real and clickable.

## Fix

- Concrete fix item
- Concrete validation item
```

Use bare GitHub issue/PR URLs when a full link is clearer. Use `#98` only when
the repository context is obvious.

When editing issue `#98`, do not add `Tracking issue: #98` or a link to issue
`#98` as a tracking reference. Link only to other relevant issues, PRs, Actions
runs, and external references.

## PR Body Format

Reference the tracked issue at the top with `Closes #N`, then list changed
areas with plain paths and include real issue/PR links. Do not use guessed
`#diff-...` anchors. Do not use generic labels such as `Issue: #98`,
`Related PR: #97`, or `PR: #99`.

Use compact icon bullets in `## Links` for useful related context. Do not add a
link to the current PR inside its own body. Do not repeat the closing issue in a
separate link line unless the issue needs extra context beyond `Closes #N`.

```markdown
Closes #42

## Links

- 🔗 Related: #41
- 🧾 Run: https://github.com/DonnieDice/protondrive-linux/actions/runs/123456789

## Summary

- Describe the main behavior or packaging change.
- Explain why it was needed.

## Changed Areas

- `README.md`
- `docs/build-packaging/packaging.md`

## Testing

- `git diff --check`
- Link to the relevant Actions run when available.
```

Numbers and links are required, but links must be stable and real. Prefer issue
links, PR links, Actions run links, and plain file paths over fragile file diff
anchors.

## Version Bumps

When merging meaningful changes, bump the version in all three files:

- `package.json`
- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`

## CI Workflows

- The visible workflow entrypoint is `.github/workflows/package-workflows.yml`.
- Package-specific implementations live under `.github/workflows/<package>/<target>/action.yml`.
- Remote GitHub Actions builds run on Linux runners.
- CommitCheck false positives can be ignored when the message follows `(#N) Description` correctly.

## Packaging State

- `compatibility-map.yml` must stay in sync with actual workflows and `docs/build-packaging/packaging.md`.
- AUR package is `proton-drive` (native build), not `proton-drive-bin`.
- AUR recipe files live in `packaging/aur/` (PKGBUILD, proton-drive.install).

## Review Bot Feedback

Before merging **any** PR, all automated review bot findings must be addressed:

- Check CodeRabbit, Qodo, and any other review bot comments on the PR.
- Every actionable comment must be either fixed or explicitly dismissed with justification.
- Do not merge with unresolved bot review items, even if CI passes.
- If a bot comment is a false positive, dismiss it on the PR conversation so it is documented.
- Re-request review after pushing fixes to ensure bots re-evaluate.

## Branch Cleanup

- Always delete remote branches after merge.
- Always delete local branches after merge.

## Key Docs

- `docs/workflow.md` - full workflow guide with step-by-step protocol.
- `docs/CONTRIBUTING.md` - detailed build, packaging, development rules.
- `docs/build-packaging/packaging.md` - canonical human-readable packaging policy.
- `packaging/compatibility-map.yml` - machine-readable target metadata.
- `docs/release-checklist.md` - pre-release checklist.
- `docs/new-build-checklist.md` - adding new package targets.
