---
name: gitlab-mcp
description: "GitLab MCP server: pinned runtime loadout, per-role least-privilege toolset wiring, and platform handoff. Use when the workforce needs the official @modelcontextprotocol/server-gitlab (MCP) integration configured, verified, or updated."
---

# GitLab MCP Server

The GitLab [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server
bridges AI tooling and GitLab's REST API. It exposes GitLab resources
as MCP tools so AI assistants interact with work items, merge requests,
repository files, CI pipelines, and more via standardized MCP tool calls.

This is the canonical, role-tuned reference for how the Hermes workforce
platform configures, invokes, and hands off GitLab MCP tooling.

## Runtime loadout

| Field | Value |
|-------|-------|
| **npm package** | `@modelcontextprotocol/server-gitlab@2025.4.25` |
| **Endpoint** | `https://gitlab.dicematrix.cloud/api/v4/mcp` |
| **Transport** | HTTP (Streamable HTTP — Claude Code ≥ v0.10, mcp-remote ≥ v0.7) |
| **sha256 (tarball)** | `3d4436611ee2f7aa77ca878fb18f382534267e92ad1687c34567cd2ffa8342f9` |
| **Auth** | OAuth 2.0 Dynamic Client Registration (RFC 7591) |
| **Pinned in** | `TOOLS.md`, `CHECKSUMS.sha256` |

> **BLOCKER NOTE:** `POST /api/v4/mcp` returns HTTP 403 under the current default
> instance config on GitLab 19.0.1 until an instance admin enables the MCP feature.
> This is an operator-only dependency — no workforce role can enable it
> (see `docs/decisions/adr-gitlab-mcp-enablement.md`).

## Supported toolsets

The server exposes toolsets (tool groups). Each workforce role is wired with a
least-privilege subset via the `X-Gitlab-Enabled-Mcp-Server-Toolsets` header.

| Toolset | Included by default | Purpose |
|---------|---------------------|---------|
| `meta` | always | Protocol metadata (initialize, etc.) |
| `core` | yes | Project info, users, basic lookups |
| `work_items` | yes | Issues, epics, scope management |
| `merge_requests` | yes | MR listing, approval, comments, diffs, suggestions |
| `repository` | yes | Repo files, branches, commits, search |
| `ci` | yes | Pipelines, jobs, triggers, artifacts |
| `wikis` | no (opt-in) | Wiki pages |
| `code_security` | no (opt-in) | Vulnerabilities, security findings, DAST/SAST |
| `duo_agent_platform` | yes | Agent platform integration |

## Per-role toolset wiring

Each role uses **its own** per-role GitLab identity (Personal Access Token
injected at runtime via `$GITLAB_TOKEN_<ROLE>`). Toolsets are restricted per role:

| Role | Toolsets | Why |
|------|----------|-----|
| `dispatcher` | `core`, `work_items` | Route issues/MRs without writing code or triggering CI |
| `engineer` | `+merge_requests`, `+repository`, `+ci` | Author code, push branches, open MRs |
| `qa` | `+merge_requests`, `+repository`, `+ci` | Independent verification |
| `reviewer` | `+merge_requests`, `+repository` | Code review only; no CI triggers, no code security |
| `security` | `+merge_requests`, `+repository`, `+ci`, `+code_security` | Security audit with expanded read |
| `platform` | `+merge_requests`, `+repository`, `+ci` | Infrastructure/runtime work |
| `release` | `+merge_requests`, `+ci` | Release coordination; no direct repo reads |
| `docs` | `+merge_requests`, `+wikis` | Documentation; no code/CI |

`meta` is always available regardless of role.

## Transport configuration

### HTTP (recommended)

```json
{
  "mcpServers": {
    "GitLab": {
      "type": "http",
      "url": "https://gitlab.dicematrix.cloud/api/v4/mcp",
      "headers": {
        "X-Gitlab-Enabled-Mcp-Server-Toolsets": "core,work_items"
      }
    }
  }
}
```

### stdio via `mcp-remote` (requires Node.js >= 20)

```json
{
  "mcpServers": {
    "GitLab": {
      "command": "npx",
      "args": ["-y", "mcp-remote",
        "https://gitlab.dicematrix.cloud/api/v4/mcp",
        "--header", "X-Gitlab-Enabled-Mcp-Server-Toolsets:core,work_items"
      ]
    }
  }
}
```

## Isolation constraints (non-negotiable)

- No `hostPath` mounts.
- No host networking.
- No privileged containers.
- No `/opt/data` sharing across roles.
- Secrets (PATs) are injected at runtime via environment variables
  (`GITLAB_TOKEN_DISPATCHER`, `GITLAB_TOKEN_ENGINEER`, etc.),
  never committed to source.

## Pickup / handoff protocol (role-tuned)

Every handoff follows the `handoff-protocol` checklist for the target role.

### Engineer pickup → handoff

- On pickup: verify candidate is at `main` HEAD + MCP loadout diff; confirm
  the pinned sha256 in `CHECKSUMS.sha256` matches the npm registry artifact.
- Prove: static lockstep tests pass with real pass/fail counts.
- Hand off: exact candidate SHA, branch, MR URL, test commands + real results,
  remaining ACs (AC6 = operator-blocked), risk notes.

### QA pickup → handoff

- Fetch candidate SHA into a clean checkout.
- Matrix: AC1 (hash pinning), AC2 (per-role isolation), AC3 (skill surface),
  AC4 (runtime config), AC5 (lockstep tests).
- Report exact pass/fail/skipped counts and execution environment.

### Reviewer pickup → handoff

- Read the complete diff; verify every file links to an AC.
- Blocking findings separated from suggestions, with file/line citations.

### Platform pickup → handoff

- Verify: loadout checksums match, `agents.yaml` has per-role toolsets,
  isolation flags set, no shared tokens in config.
- Prove: lockstep tests pass, no role exceeds least-privilege.

## Verification and lockstep tests

Run the lockstep test suite to verify all three `TOOLS.md` ↔ `CHECKSUMS.sha256`
/`agents.yaml` invariants:

```bash
python -m pytest tests/unit/test_mcp_checksum_lockstep.py -v
```

`GISSUE_90_MCP_SERVER_SHA256` may be set to assert the exact expected checksum
supports CI reproducibility, or the file itself may be updated as the source
of truth.

## Common update workflow

1. Bump version + sha256 in `TOOLS.md` and `CHECKSUMS.sha256`.
2. Re-run lockstep tests: `python -m pytest tests/unit/test_mcp_checksum_lockstep.py -v`.
3. Verify the new sha256 against the npm registry artifact:
   `curl -sL <registry-url> | sha256sum`.
4. Open MR; request reviewer + security + QA gates.

## Related files

- `TOOLS.md` — runtime loadout with pinned versions
- `CHECKSUMS.sha256` — sha256 checksums for pinned artifacts
- `agents.yaml` — per-role identity and toolset wiring
- `tests/unit/test_mcp_checksum_lockstep.py` — static lockstep tests
- `docs/decisions/adr-gitlab-mcp-enablement.md` — operator enablement decision record