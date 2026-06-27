---
title: "CI Authority and GitHub Mirroring"
created: 2026-05-28
updated: 2026-06-27
type: guide
tags: [ci]
sources:
  - []
---


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

## Doc audit pipeline

The AI-assisted doc audit pipeline (jobs: `docs:detect-changes`,
`docs:resolve-mapping`, `docs:audit-gate`, `docs:auto-update`) runs exclusively
in GitLab CI, consistent with the GitLab authority model. The shared
`.rules:doc_audit` rule set restricts these jobs to the `main` branch and
optional scheduled, web, or API triggers:

```yaml
.rules:doc_audit:
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_PIPELINE_SOURCE == "schedule" && $RUN_DOC_AUDIT == "true"'
    - if: '$CI_PIPELINE_SOURCE == "web" && $RUN_DOC_AUDIT == "true"'
    - if: '$CI_PIPELINE_SOURCE == "api" && $RUN_DOC_AUDIT == "true"'
    - when: never
```

The `main`-only branch condition prevents doc audit pipelines from running on
feature branches, topic branches, or forks — audit results are only meaningful
against the integration branch, and the push token used by `docs:auto-update` to
open merge requests should only be delegated from `main`.

The `docs:auto-update` job extends `.rules:doc_audit` but overrides web and API
triggers to manual-only, so automated documentation updates always require human
acknowledgment via the run interface:

```yaml
docs:auto-update:
  extends: .rules:doc_audit
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_PIPELINE_SOURCE == "schedule" && $RUN_DOC_AUDIT == "true"'
    - if: '$CI_PIPELINE_SOURCE == "web" && $RUN_DOC_AUDIT == "true"'
      when: manual
      allow_failure: true
    - if: '$CI_PIPELINE_SOURCE == "api" && $RUN_DOC_AUDIT == "true"'
      when: manual
      allow_failure: true
    - when: never
```

No equivalent doc audit pipeline exists in GitHub Actions — the authority model
assigns documentation quality to GitLab CI's private runner infrastructure.

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
