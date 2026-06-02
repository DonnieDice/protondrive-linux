"""Tests for CI build artifact key and manifest helpers."""
import json
import pathlib
import shlex
import shutil
import subprocess

import pytest


def _run(repo_root: pathlib.Path, command: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-c", command],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_compute_build_key_is_deterministic_and_prefixed(repo_root, have_bash):
    script = repo_root / "scripts" / "ci" / "lib" / "compute-build-key.sh"
    command = f"WEBCLIENTS_COMMIT=abc123 {shlex.quote(str(script))} deb debian.12"

    first = _run(repo_root, command)
    second = _run(repo_root, command)

    assert first.returncode == 0, first.stderr
    assert second.returncode == 0, second.stderr
    assert first.stdout == second.stdout
    assert first.stdout.startswith("deb-debian.12-")
    digest = first.stdout.strip().rsplit("-", 1)[1]
    assert len(digest) == 64
    int(digest, 16)


def test_compute_build_key_changes_when_build_env_changes(repo_root, have_bash):
    script = repo_root / "scripts" / "ci" / "lib" / "compute-build-key.sh"
    base = _run(repo_root, f"WEBCLIENTS_COMMIT=abc123 {shlex.quote(str(script))} deb debian.12")
    changed = _run(repo_root, f"WEBCLIENTS_COMMIT=def456 {shlex.quote(str(script))} deb debian.12")

    assert base.returncode == 0, base.stderr
    assert changed.returncode == 0, changed.stderr
    assert base.stdout != changed.stdout


def test_artifact_manifest_records_build_key_and_gitlab_context(repo_root, have_bash, tmp_path):
    if not shutil.which("node"):
        pytest.skip("node not available")

    script = repo_root / "scripts" / "ci" / "lib" / "write-artifact-manifest.sh"
    artifact = tmp_path / "proton-drive_1.0.0_debian12_amd64.deb"
    out_dir = tmp_path / "metadata"
    artifact.write_bytes(b"package-bytes")

    command = " ".join(
        [
            f"ARTIFACT_MANIFEST_DIR={shlex.quote(str(out_dir))}",
            "BUILD_KEY=deb-debian.12-testkey",
            "CI_JOB_ID=123",
            "CI_JOB_NAME=build:deb:debian-12",
            "CI_PIPELINE_ID=456",
            f"{shlex.quote(str(script))}",
            "proton-drive-debian12",
            "deb",
            "debian-12",
            "amd64",
            shlex.quote(str(artifact)),
        ]
    )
    result = _run(repo_root, command)

    assert result.returncode == 0, result.stderr
    manifest = json.loads((out_dir / "proton-drive-debian12.manifest.json").read_text())
    assert manifest["build_key"] == "deb-debian.12-testkey"
    assert manifest["build_key_schema"] == "proton-drive-build-key-v1"
    assert manifest["gitlab"]["job_id"] == "123"
    assert manifest["gitlab"]["job_name"] == "build:deb:debian-12"
    assert manifest["files"][0]["sha256"]
