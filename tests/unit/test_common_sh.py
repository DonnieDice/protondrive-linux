"""Unit tests for scripts/ci/deploy/_common.sh (bash) driven from pytest.

Each test sources the library in a subshell and exercises one function in
isolation. Notably covers the VM_SSH_KEY normalization that fixes the GitLab
File-variable "error in libcrypto" failure (missing trailing newline / CRLF).
"""
import pathlib
import shlex
import subprocess

REPO = pathlib.Path(__file__).resolve().parents[2]
COMMON = REPO / "scripts" / "ci" / "deploy" / "_common.sh"


def _bash(snippet: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", "-c", snippet], capture_output=True, text=True)


def test_common_sh_sources_cleanly(have_bash):
    r = _bash(f'source {shlex.quote(str(COMMON))}; type deploy_run >/dev/null && echo OK')
    assert "OK" in r.stdout, r.stderr


def test_key_normalization_fixes_crlf_and_missing_newline(have_bash, have_ssh_keygen, tmp_path):
    # A genuine key, then mangled the way GitLab File vars break it.
    key = tmp_path / "id"
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
    mangled = key.read_text().replace("\n", "\r\n").rstrip("\r\n")  # CRLF + no trailing newline
    snippet = f"""
        set -e
        source {shlex.quote(str(COMMON))}
        export VM_SSH_KEY={shlex.quote(mangled)}
        _pd_ssh_init
        # normalized file must: end in LF, contain no CR, and parse as a key
        [ "$(tail -c1 "$_PD_KEYFILE" | od -An -tx1 | tr -d ' ')" = "0a" ]
        ! grep -qU $'\\r' "$_PD_KEYFILE"
        ssh-keygen -y -f "$_PD_KEYFILE" >/dev/null
        echo NORMALIZED_OK
    """
    r = _bash(snippet)
    assert "NORMALIZED_OK" in r.stdout, f"normalization failed:\nSTDOUT:{r.stdout}\nSTDERR:{r.stderr}"


def test_invalid_key_is_rejected_with_clear_error(have_bash, have_ssh_keygen):
    snippet = f"""
        source {shlex.quote(str(COMMON))}
        export VM_SSH_KEY="not a real private key"
        _pd_ssh_init 2>&1 || true
    """
    r = _bash(snippet)
    assert "did not parse as a valid private key" in (r.stdout + r.stderr)


def test_find_artifact_matches_glob(have_bash, tmp_path):
    art = tmp_path / "artifacts"
    art.mkdir()
    (art / "proton-drive_2.0.0_debian12_amd64.deb").write_bytes(b"x")
    snippet = f"""
        export VM_SSH_KEY=dummy ARTIFACT_DIR={shlex.quote(str(art))}
        source {shlex.quote(str(COMMON))}
        # stub the key init so find_artifact can run without a real key
        _pd_ssh_init() {{ :; }}
        find_artifact 'proton-drive_*_debian12_*.deb'
    """
    r = _bash(snippet)
    assert "debian12" in r.stdout, r.stderr
