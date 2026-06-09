# AI Documentation Audit Pipeline

This repository can run an AI-assisted documentation audit from GitLab CI. The
pipeline maps changed source files to documentation targets, asks an LLM whether
those docs are stale, and can open a documentation merge request with proposed
updates.

The implementation is intentionally repo-native:

- `docs/mapping.yaml` is the source of truth for source-to-doc relationships.
- `scripts/ci/resolve-mapping.py` produces `docs/affected_docs.json`.
- `scripts/ci/ai-doc-gate.sh` writes `docs/stale_docs.json` and enforces the
  schedule vs release-gate policy.
- `scripts/ci/ai-doc-update.sh` proposes documentation updates through the LLM.
- `scripts/ci/apply-doc-patch.py` limits writes to documentation paths.

## Triggering

The main release pipeline remains gated. Documentation audits run only when a
pipeline is created with `RUN_DOC_AUDIT=true`.

Typical scheduled audit variables:

```text
RUN_DOC_AUDIT=true
DOC_AUDIT_WINDOW_HOURS=24
```

Manual/API audit variables:

```text
RUN_DOC_AUDIT=true
DOC_AUDIT_MODE=release_gate
```

## Required Secrets

Set one of these CI/CD variables:

```text
DEEPSEEK_API_KEY
OPENAI_API_KEY
```

For automatic merge-request creation from `docs:auto-update`, set:

```text
DOC_AUDIT_PUSH_TOKEN
```

The token must have permission to push a branch to the project. The job does not
store this token in repository files.

## Section Updates

Section-scoped updates require explicit markers:

```markdown
<!-- BEGIN SECTION: Section Name -->
Current documentation content.
<!-- END SECTION: Section Name -->
```

If a mapped section does not have markers yet, `docs:auto-update` skips that
target instead of rewriting the entire file. File-scoped updates are allowed only
for documentation paths configured by `docs/mapping.yaml`.

## Guardrails

- Scheduled audits warn and continue if stale docs are found.
- Release-gate audits fail when critical mapped docs are stale.
- Large diffs are treated as manual-review cases rather than sent to the LLM.
- AI-generated content is committed to a dedicated branch and proposed through a
  merge request for human review.
