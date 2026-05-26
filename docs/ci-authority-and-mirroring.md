# CI Authority and GitHub Mirroring

`protondrive-linux` is designed to keep one authoritative CI/CD system.

## Source of truth

GitLab CI is the authoritative system for:

- full build matrix execution
- VM install/runtime tests
- package artifacts
- signing
- publishing
- release creation

The GitHub repository is a public mirror and contributor surface. GitHub Actions
must not independently publish release artifacts unless the project explicitly
changes CI authority.

## Why GitLab owns full CI/CD

The full package and install-test pipeline depends on private infrastructure:

- the self-hosted GitLab runner
- the Unraid/LAN VM matrix
- private signing and publishing credentials
- internal SSH inventory for package/runtime validation

Mirrored GitHub commits should not trigger the same full build/release flow a
second time. Duplicating full CI/CD across GitLab and GitHub creates drift,
double-publishing risk, duplicated secrets, and inconsistent release provenance.

## GitHub Actions policy

GitHub Actions may run:

- login/session routing regression checks
- sync regression checks
- Rust regression tests that do not need private runners
- issue/PR labeling automation
- explicit manual compatibility workflows via `workflow_dispatch`

GitHub Actions must not automatically run package build or publishing jobs on:

- mirrored pushes
- pull requests
- tags
- GitHub release events

The package workflow implementations under `.github/workflows/` are retained for
manual checks and maintenance, but they are not the release authority.

## Release policy

Release artifacts should be built once by GitLab CI, then optionally mirrored to
GitHub Releases. GitHub should not rebuild release artifacts independently from
the same source tag.

Recommended release flow:

```text
GitLab tag/release pipeline
  -> build packages
  -> run VM install tests
  -> sign artifacts
  -> publish GitLab release
  -> optionally upload the same artifacts to GitHub Releases
```

## GitHub PR policy

If GitHub remains a mirror but accepts PRs, full validation should happen in
GitLab before merge:

```text
GitHub PR
  -> public GitHub sanity checks
  -> import branch/MR into GitLab
  -> GitLab full CI and VM tests
  -> merge in the authoritative repository
  -> mirror result back to GitHub
```

Do not merge a GitHub PR solely because GitHub sanity checks passed; those checks
are intentionally not equivalent to the full GitLab package/VM pipeline.

## Disaster recovery

If GitHub ever becomes the primary repository, promote CI authority deliberately:

1. provision GitHub self-hosted runners or a GitHub-to-GitLab trigger bridge
2. migrate required secrets to the chosen secret manager
3. update this document and branch protection rules
4. ensure exactly one system owns publishing

Until that promotion is complete, GitLab remains authoritative.
