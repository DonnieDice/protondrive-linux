# Multi-Agent Coordination

Use this guide when multiple people or agents are working on the repository at the same time.

## Branch Strategy

Keep each workstream on its own branch:

```text
dev                         shared integration branch
docs/comprehensive-docs     documentation-only branch
fix/fedora-build-patches    Fedora/package fix branch
fix/go-build-correctness     Go build/test fix branch
```

Open pull requests into `dev`, not directly into `main`, unless maintainers choose a different release flow.

## Documentation Branch Scope

The documentation branch should normally touch:

```text
README.md
CONTRIBUTING.md
docs/
```

Avoid touching these while package/build work is active:

```text
scripts/
.github/workflows/
internal/
cmd/
main.go
go.mod
go.sum
```

If docs must describe active build changes, prefer adding or updating files under `docs/` instead of editing implementation files.

## Build Fix Branch Scope

Package/build branches should normally touch:

```text
cmd/
internal/
scripts/
.github/workflows/
go.mod
go.sum
```

When behavior changes, add a short note to the PR describing which documentation page needs an update. The docs branch can pick that up after the build fix lands.

## Merge Order

Preferred order when build fixes and docs are active together:

1. Merge build/package fixes into `dev`.
2. Rebase `docs/comprehensive-docs` on the updated `origin/dev`.
3. Resolve any docs conflicts.
4. Merge docs into `dev`.

That keeps correctness-sensitive build changes as the source of truth, then lets documentation describe the final behavior.

## Keeping the Docs Branch Fresh

From the docs branch:

```bash
git fetch origin
git rebase origin/dev
```

After resolving conflicts:

```bash
git push --force-with-lease
```

Use `--force-with-lease` instead of a plain force push so you do not overwrite another person's newer remote work.

## Conflict Policy

When a conflict includes both behavior changes and prose:

- Keep the behavior from the latest `dev`.
- Keep documentation structure from the docs branch when it remains accurate.
- Update the prose to describe the behavior that actually landed.
- Do not document planned behavior as current behavior.

## Handoff Notes

Every branch should leave enough context for the next person:

- What files changed.
- What behavior changed.
- What was verified.
- What documentation still needs updating.

For documentation-only PRs, verification can be limited to markdown review and `git diff --check`.
