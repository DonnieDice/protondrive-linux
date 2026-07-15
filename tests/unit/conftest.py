"""Shared pytest fixtures for the protondrive-linux script unit tests."""

import pathlib
import shutil
import sys

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
# Make the Robot VM matrix importable as a plain module.
sys.path.insert(0, str(REPO_ROOT / "tests" / "robot" / "vars"))


def _is_posix_bash_available() -> bool:
    """True if `bash` exists AND it's a real POSIX bash (not MSYS-emulated,
    not WSL-stub). CI Linux returns True. Windows (Git-Bash or WSL stub) returns
    False because MSYS path translation / WSL disk-attach failures break the
    bash-script subprocess tests."""
    if sys.platform.startswith("win"):
        # MSYS path translation mangles Windows paths; WSL stub can't even
        # attach the disk in subprocess contexts. Skip both cleanly.
        return False
    return shutil.which("bash") is not None


@pytest.fixture(scope="session")
def repo_root() -> pathlib.Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def have_bash():
    if not shutil.which("bash"):
        pytest.skip("bash not available")
    return True


@pytest.fixture(scope="session")
def have_posix_bash(have_bash):
    """Skips tests that shell out to bash when running on Windows (Git-Bash-MSYS
    path translation or WSL stub failures break Windows-path-in-script args)."""
    if not _is_posix_bash_available():
        pytest.skip("bash-script subprocess tests not supported on Windows")
    return True


@pytest.fixture(scope="session")
def have_ssh_keygen():
    if not shutil.which("ssh-keygen"):
        pytest.skip("ssh-keygen not available")
    return True
