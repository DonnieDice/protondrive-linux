"""Static checksum-lockstep tests for the GitLab MCP runtime loadout (Work Item #90).

Enforces the following invariants:
  AC1 — The pinned GitLab MCP server version and sha256 in TOOLS.md are matched
        by an identical entry in CHECKSUMS.sha256.
  AC2 — Each workforce role's toolset allowlist in agents.yaml is a subset of
        the declared least-privilege set, and per-role token env-var names are
        unique and non-empty (no shared tokens).
  AC5 — The checksum lockstep holds in both directions and the GIIssue_90 env
        override (if set) matches the pinned value.

Run:  python -m pytest tests/unit/test_mcp_checksum_lockstep.py -v
"""

import os
import re

import pytest
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _read_tools_md():
    path = os.path.join(REPO_ROOT, "TOOLS.md")
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _read_checksums():
    path = os.path.join(REPO_ROOT, "CHECKSUMS.sha256")
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _read_agents_yaml():
    path = os.path.join(REPO_ROOT, "agents.yaml")
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# Declared least-privilege toolset sets (mirrors TOOLS.md / agents.yaml table)
LEAST_PRIVILEGE = {
    "dispatcher": {"core", "work_items"},
    "engineer": {"core", "work_items", "merge_requests", "repository", "ci"},
    "qa": {"core", "work_items", "merge_requests", "repository", "ci"},
    "reviewer": {"core", "work_items", "merge_requests", "repository"},
    "security": {"core", "work_items", "merge_requests", "repository", "ci", "code_security"},
    "platform": {"core", "work_items", "merge_requests", "repository", "ci"},
    "release": {"core", "work_items", "merge_requests", "ci"},
    "docs": {"core", "work_items", "merge_requests", "wikis"},
}

# Forbidden toolsets per role (role must NOT have these even as opt-in)
FORBIDDEN = {
    "dispatcher": {"repository", "ci", "wikis", "code_security"},
    "engineer": {"wikis", "code_security"},
    "qa": {"wikis", "code_security"},
    "reviewer": {"ci", "wikis", "code_security"},
    "security": {"wikis"},
    "platform": {"wikis", "code_security"},
    "release": {"repository", "wikis", "code_security"},
    "docs": {"repository", "ci", "code_security"},
}


# ─── AC1: TOOLS.md ↔ CHECKSUMS.sha256 lockstep ────────────────────────────────

def test_tools_md_contains_pinned_gitlab_mcp_version():
    """TOOLS.md must declare the exact pinned version (2025.4.25)."""
    content = _read_tools_md()
    assert "2025.4.25" in content, "TOOLS.md is missing the pinned version 2025.4.25"


def test_tools_md_contains_pinned_sha256():
    """TOOLS.md must declare the exact pinned sha256."""
    content = _read_tools_md()
    expected = "3d4436611ee2f7aa77ca878fb18f382534267e92ad1687c34567cd2ffa8342f9"
    assert expected in content, (
        "TOOLS.md is missing the pinned sha256 for the GitLab MCP server tarball"
    )


def test_checksums_file_contains_pinned_sha256():
    """CHECKSUMS.sha256 must contain the exact pinned sha256."""
    content = _read_checksums()
    expected = "3d4436611ee2f7aa77ca878fb18f382534267e92ad1687c34567cd2ffa8342f9"
    assert expected in content, (
        "CHECKSUMS.sha256 is missing the pinned sha256"
    )


def test_checksums_contains_matching_version_label():
    """CHECKSUMS.sha256 must reference the tarball name with the right version."""
    content = _read_checksums()
    assert "server-gitlab-2025.4.25.tgz" in content, (
        "CHECKSUMS.sha256 does not reference server-gitlab-2025.4.25.tgz"
    )


def test_sha256_in_tools_md_matches_checksums():
    """The sha256 declared in TOOLS.md must appear exactly in CHECKSUMS.sha256."""
    tools = _read_tools_md()
    checksums = _read_checksums()
    # Extract the 64-hex hash from TOOLS.md
    match = re.search(r"\b([0-9a-f]{64})\b", tools)
    assert match, "No 64-hex sha256 found in TOOLS.md"
    sha_in_tools = match.group(1)
    assert sha_in_tools in checksums, (
        f"sha256 {sha_in_tools} from TOOLS.md not found in CHECKSUMS.sha256"
    )


def test_env_override_matches_pinned():
    """If GISSUE_90_MCP_SERVER_SHA256 is set (CI assertion), it must match the
    value pinned in CHECKSUMS.sha256."""
    env_val = os.environ.get("GISSUE_90_MCP_SERVER_SHA256")
    if not env_val:
        pytest.skip("GISSUE_90_MCP_SERVER_SHA256 not set; skipping env override check")
    checksums = _read_checksums()
    assert env_val in checksums, (
        f"GISSUE_90_MCP_SERVER_SHA256 ({env_val}) not found in CHECKSUMS.sha256"
    )
    assert len(env_val) == 64, "sha256 must be 64 hex characters"


# ─── AC2: Per-role toolset least-privilege in agents.yaml ─────────────────────

def test_agents_yaml_has_all_roles():
    """agents.yaml must define every required workforce role."""
    content = _read_agents_yaml()
    data = yaml.safe_load(content)
    roles = set(data.get("roles", {}).keys())
    expected = {"dispatcher", "engineer", "qa", "reviewer", "security",
                "platform", "release", "docs"}
    assert roles == expected, f"roles mismatch: got {roles}, want {expected}"


def test_each_role_toolset_is_subset_of_least_privilege():
    """Each role's toolsets must be a subset of its declared least-privilege set."""
    content = _read_agents_yaml()
    data = yaml.safe_load(content)
    for role_name, role_cfg in data["roles"].items():
        role_toolsets = set(role_cfg.get("toolsets", []))
        allowed = LEAST_PRIVILEGE[role_name]
        excess = role_toolsets - allowed
        assert not excess, (
            f"Role '{role_name}' has toolsets {excess} that exceed the "
            f"declared least-privilege set {allowed}"
        )


def test_each_role_has_forbidden_toolsets_excluded():
    """Each role must not include any explicitly forbidden toolset."""
    content = _read_agents_yaml()
    data = yaml.safe_load(content)
    for role_name, role_cfg in data["roles"].items():
        role_toolsets = set(role_cfg.get("toolsets", []))
        forbidden = FORBIDDEN[role_name]
        overlap = role_toolsets & forbidden
        assert not overlap, (
            f"Role '{role_name}' must not include forbidden toolsets {overlap}"
        )


def test_each_role_has_unique_nonempty_token_env():
    """Each role must have a unique, non-empty gitlab_token_env var name."""
    content = _read_agents_yaml()
    data = yaml.safe_load(content)
    seen_envs = set()
    for role_name, role_cfg in data["roles"].items():
        token_env = role_cfg.get("gitlab_token_env")
        assert token_env, f"Role '{role_name}' has no gitlab_token_env set"
        assert token_env != "GITLAB_TOKEN", (
            f"Role '{role_name}' uses generic GITLAB_TOKEN — must be role-specific"
        )
        assert token_env not in seen_envs, (
            f"Role '{role_name}' reuses token env {token_env} — tokens must be unique per role"
        )
        seen_envs.add(token_env)


def test_no_shared_token_in_agents_yaml():
    """No generic 'GITLAB_TOKEN' (without role suffix) may be used as an identity."""
    content = _read_agents_yaml()
    data = yaml.safe_load(content)
    for role_name, role_cfg in data["roles"].items():
        token_env = role_cfg.get("gitlab_token_env", "")
        # Generic token (no role suffix) is forbidden
        if token_env == "GITLAB_TOKEN":
            pytest.fail(
                f"Role '{role_name}' uses generic GITLAB_TOKEN — shared tokens "
                f"are forbidden; use GITLAB_TOKEN_<ROLE> instead"
            )


def test_role_identities_are_unique():
    """Each role must have a distinct identity string."""
    content = _read_agents_yaml()
    data = yaml.safe_load(content)
    identities = [
        role_cfg.get("identity") for role_cfg in data["roles"].values()
    ]
    assert len(identities) == len(set(identities)), (
        "Role identities are not unique — duplicate identities found"
    )


# ─── AC5: Lockstep bidirectional consistency ──────────────────────────────────

def test_mcp_server_block_in_agents_yaml_matches_tools():
    """The pinned_version and sha256 in agents.yaml must match TOOLS.md."""
    tools = _read_tools_md()
    agents = _read_agents_yaml()
    agents_data = yaml.safe_load(agents)
    mcp_cfg = agents_data.get("mcp", {}).get("gitlab", {})

    # Extract sha256 from TOOLS.md
    tools_sha = re.search(r"\b([0-9a-f]{64})\b", tools)
    assert tools_sha, "No sha256 found in TOOLS.md"

    # Extract version from TOOLS.md
    assert "2025.4.25" in tools

    assert mcp_cfg.get("pinned_version") == "2025.4.25", (
        f"agents.yaml mcp.gitlab.pinned_version ({mcp_cfg.get('pinned_version')}) "
        f"does not match TOOLS.md (2025.4.25)"
    )
    assert mcp_cfg.get("sha256") == tools_sha.group(1), (
        f"agents.yaml mcp.gitlab.sha256 ({mcp_cfg.get('sha256')}) does not "
        f"match TOOLS.md ({tools_sha.group(1)})"
    )


def test_runtime_isolation_flags_in_agents_yaml():
    """agents.yaml must declare all required isolation constraints."""
    content = _read_agents_yaml()
    data = yaml.safe_load(content)
    isolation = data.get("runtime", {}).get("isolation", {})
    for flag in ("hostPath", "hostNetwork", "privileged", "shareOptData", "secrets_in_source"):
        assert flag in isolation, f"Missing isolation flag: {flag}"
        assert isolation[flag] is False, (
            f"isolation.{flag} must be False, got {isolation[flag]}"
        )
