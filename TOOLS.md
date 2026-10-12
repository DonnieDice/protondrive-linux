# Runtime Toolchain Loadout

> Pinned tool versions for the Hermes workforce platform runtime. Every tool
> listed here is pinned with a nonce-verified sha256 checksum from its released
> archive. Only the versions below are trusted; all others must be explicitly
> approved and added through this loadout.

## MCP Servers

### GitLab MCP Server (official)

| Field | Value |
|-------|-------|
| **Component** | `modelcontextprotocol/gitlab@2025.4.25` |
| **Protocol** | Model Context Protocol (MCP) |
| **Endpoint** | `https://gitlab.dicematrix.cloud/api/v4/mcp` |
| **Transport** | HTTP (Streamable HTTP — Claude Code ≥ v0.10, mcp-remote ≥ v0.7) |
| **Version** | `2025.4.25` |
| **Released** | 2026-04-11 |
| **Tarball** | `server-gitlab-2025.4.25.tgz` |
| **sha256** | `3d4436611ee2f7aa77ca878fb18f382534267e92ad1687c34567cd2ffa8342f9` |
| **License** | MIT |
| **Upstream** | [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) |

**Status:** PINNED — static loadout shipped; live end-to-end usage pending operator-only MCP feature enablement (see `docs/decisions/adr-gitlab-mcp-enablement.md`).

### Auth model

Each workforce role connects its own existing per-role GitLab identity
(Personal Access Token minted for the role). No shared or privileged identity
is used. The GitLab MCP server authenticates via **OAuth 2.0 Dynamic Client
Registration** (RFC 7591), which lets each role register itself at connection
time and receive a per-connection access token scoped by the role's own PAT.

### Per-role toolsets

Each role restricts which MCP toolsets it permits by setting the
`X-Gitlab-Enabled-Mcp-Server-Toolsets` header at connection. Allowed values
(for the ProtonDrive repo project):

| Role | Allowed toolsets |
|------|------------------|
| `dispatcher` | `core`, `work_items` |
| `engineer` | `core`, `work_items`, `merge_requests`, `repository`, `ci` |
| `qa` | `core`, `work_items`, `merge_requests`, `repository`, `ci` |
| `reviewer` | `core`, `work_items`, `merge_requests`, `repository` |
| `security` | `core`, `work_items`, `merge_requests`, `repository`, `ci`, `code_security` |
| `platform` | `core`, `work_items`, `merge_requests`, `repository`, `ci` |
| `release` | `core`, `work_items`, `merge_requests`, `ci` |
| `docs` | `core`, `work_items`, `merge_requests`, `wikis` |

`meta` tools are always present regardless of role.

### Isolation constraints (non-negotiable)

- No `hostPath` mounts.
- No host networking.
- No privileged containers.
- No `/opt/data` sharing across roles.
- Secrets are never baked into images; per-role GitLab tokens are injected
  at connection time via environment variables (`GITLAB_TOKEN_<ROLE>`), not
  persisted in the source repository or CI artifacts.

## Toolchain

All existing runtime tools (Rust, Node.js, Python, CI linters) are documented
in `docs/architecture/architecture.md` and `justfile`. This file (TOOLS.md)
tracks only new, security-sensitive loadout components requiring checksum
pinning.

## Verification

The static checksum lockstep tests in `tests/unit/test_mcp_checksum_lockstep`
verify that:

1. Every pinned version in TOOLS.md matches an entry in `CHECKSUMS.sha256`.
2. Each workforce role's role-specific toolset allowlist is a subset of the
   declared least-privilege set.
3. No role's toolset set includes `wikis` or `code_security` unless explicitly
   declared above.
4. `GISSUE_90_MCP_SERVER_SHA256` environment variable, if set, matches the
   pinned checksum (supports reproducible CI assertions).

Run lockstep checks locally with:

```bash
python -m pytest tests/unit/test_mcp_checksum_lockstep.py -v
```