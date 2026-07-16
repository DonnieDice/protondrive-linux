"""Tests for CI build artifact key and manifest helpers."""

import hashlib
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import tarfile

import pytest


def _run(
    repo_root: pathlib.Path, command: str, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-c", command],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_compute_build_key_is_deterministic_and_prefixed(repo_root, have_posix_bash):
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


def test_compute_build_key_changes_when_build_env_changes(repo_root, have_posix_bash):
    script = repo_root / "scripts" / "ci" / "lib" / "compute-build-key.sh"
    base = _run(repo_root, f"WEBCLIENTS_COMMIT=abc123 {shlex.quote(str(script))} deb debian.12")
    changed = _run(repo_root, f"WEBCLIENTS_COMMIT=def456 {shlex.quote(str(script))} deb debian.12")

    assert base.returncode == 0, base.stderr
    assert changed.returncode == 0, changed.stderr
    assert base.stdout != changed.stdout


def test_artifact_manifest_records_build_key_and_gitlab_context(
    repo_root, have_posix_bash, tmp_path
):
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


def _write_fake_curl(path: pathlib.Path) -> None:
    path.write_text(
        """#!/bin/sh
set -eu
output=''
upload=''
while [ \"$#\" -gt 0 ]; do
  case \"$1\" in
    --output) output=\"$2\"; shift 2 ;;
    --upload-file) upload=\"$2\"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n \"$upload\" ]; then
  cp \"$upload\" \"$FAKE_UPLOAD_COPY\"
  printf '%s' \"${FAKE_HTTP_STATUS:-201}\"
elif [ \"${FAKE_HTTP_STATUS:-200}\" = 200 ]; then
  cp \"$FAKE_CACHE_ARCHIVE\" \"$output\"
  printf '200'
else
  printf '%s' \"$FAKE_HTTP_STATUS\"
fi
""",
        encoding="utf-8",
    )
    path.chmod(0o755)


def _write_cache_archive(path: pathlib.Path, build_key: str, payload: bytes) -> None:
    stage = path.parent / "cache-stage"
    artifact = stage / "artifacts" / "package.test"
    metadata = stage / ".artifact-cache"
    artifact.parent.mkdir(parents=True)
    metadata.mkdir(parents=True)
    artifact.write_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    (metadata / "build-key").write_text(f"{build_key}\n", encoding="utf-8")
    (metadata / "SHA256SUMS").write_text(f"{digest}  artifacts/package.test\n", encoding="utf-8")
    with tarfile.open(path, "w:gz") as archive:
        archive.add(stage, arcname=".")


def _cache_env(tmp_path: pathlib.Path, fake_bin: pathlib.Path) -> dict[str, str]:
    return {
        **os.environ,
        "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
        "BUILD_ARTIFACT_CACHE_WORK_DIR": str(tmp_path / "work"),
        "BUILD_ARTIFACT_DIR": str(tmp_path / "output-artifacts"),
        "BUILD_KEY": "deb-debian.12-test-key",
        "BUILD_PACKAGE_TYPE": "deb",
        "BUILD_TARGET_LABEL": "debian.12",
        "CI_API_V4_URL": "https://gitlab.example.test/api/v4",
        "CI_PROJECT_ID": "74",
        "CI_JOB_TOKEN": "test-token",
        "CI_JOB_NAME": "build:deb:debian-12",
        "CI_JOB_NAME_SLUG": "build-deb-debian-12",
    }


def test_build_artifact_cache_restores_verified_hit(repo_root, have_posix_bash, tmp_path):
    script = repo_root / "scripts" / "ci" / "lib" / "build-artifact-cache.sh"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_curl(fake_bin / "curl")
    archive = tmp_path / "cache.tar.gz"
    _write_cache_archive(archive, "deb-debian.12-test-key", b"cached-package")
    env = _cache_env(tmp_path, fake_bin)
    env["FAKE_CACHE_ARCHIVE"] = str(archive)

    result = subprocess.run(
        ["sh", str(script), "restore"],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "output-artifacts" / "package.test").read_bytes() == b"cached-package"
    assert "hit: restored verified artifacts" in result.stdout


def test_build_artifact_cache_rejects_wrong_key(repo_root, have_posix_bash, tmp_path):
    script = repo_root / "scripts" / "ci" / "lib" / "build-artifact-cache.sh"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_curl(fake_bin / "curl")
    archive = tmp_path / "cache.tar.gz"
    _write_cache_archive(archive, "deb-debian.12-other-key", b"stale-package")
    env = _cache_env(tmp_path, fake_bin)
    env["FAKE_CACHE_ARCHIVE"] = str(archive)

    result = subprocess.run(
        ["sh", str(script), "restore"],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert not (tmp_path / "output-artifacts").exists()
    assert "build key does not match" in result.stdout


def test_build_artifact_cache_publishes_completed_artifacts(repo_root, have_posix_bash, tmp_path):
    script = repo_root / "scripts" / "ci" / "lib" / "build-artifact-cache.sh"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_curl(fake_bin / "curl")
    artifact_dir = tmp_path / "output-artifacts"
    artifact_dir.mkdir()
    (artifact_dir / "package.test").write_bytes(b"fresh-package")
    uploaded = tmp_path / "uploaded.tar.gz"
    env = _cache_env(tmp_path, fake_bin)
    env["FAKE_UPLOAD_COPY"] = str(uploaded)

    result = subprocess.run(
        ["sh", str(script), "publish"],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert uploaded.is_file()
    with tarfile.open(uploaded, "r:gz") as archive:
        names = {name.removeprefix("./") for name in archive.getnames()}
        assert "artifacts/package.test" in names
        assert ".artifact-cache/build-key" in names
    assert ".artifact-cache/SHA256SUMS" in names
    assert "published deb-debian.12-test-key" in result.stdout


def test_build_artifact_cache_does_not_publish_failed_job_artifacts(
    repo_root, have_posix_bash, tmp_path
):
    script = repo_root / "scripts" / "ci" / "lib" / "build-artifact-cache.sh"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_curl(fake_bin / "curl")
    artifact_dir = tmp_path / "output-artifacts"
    artifact_dir.mkdir()
    (artifact_dir / "partial.test").write_bytes(b"partial-package")
    uploaded = tmp_path / "uploaded.tar.gz"
    env = _cache_env(tmp_path, fake_bin)
    env["FAKE_UPLOAD_COPY"] = str(uploaded)
    env["CI_JOB_STATUS"] = "failed"

    result = subprocess.run(
        ["sh", str(script), "publish"],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert not uploaded.exists()
    assert "refusing to publish partial artifacts" in result.stdout
