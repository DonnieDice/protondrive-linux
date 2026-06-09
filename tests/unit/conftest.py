"""Shared pytest fixtures for the protondrive-linux script unit tests."""
import pathlib
import shutil
import sys

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
# Make the Robot VM matrix importable as a plain module.
sys.path.insert(0, str(REPO_ROOT / "tests" / "robot" / "vars"))


@pytest.fixture(scope="session")
def repo_root() -> pathlib.Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def have_bash():
    if not shutil.which("bash"):
        pytest.skip("bash not available")
    return True


@pytest.fixture(scope="session")
def have_ssh_keygen():
    if not shutil.which("ssh-keygen"):
        pytest.skip("ssh-keygen not available")
    return True
