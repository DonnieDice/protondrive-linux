"""Shared pytest fixtures for the protondrive-linux script unit tests."""

import importlib.util
import pathlib
import shutil
import sys

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
# Make the Robot VM matrix importable as a plain module.
sys.path.insert(0, str(REPO_ROOT / "tests" / "robot" / "vars"))
# Make the scripts/ci/ Python helpers importable as plain modules.
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))


def _load_script_module(name: str, path: pathlib.Path):
    """Import a sibling Python script (no __init__.py in scripts/ci/) by file
    path so its functions are unit-testable without subprocess."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault(name, module)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def repo_root() -> pathlib.Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def resolve_mapping_module(repo_root):
    return _load_script_module("resolve_mapping", repo_root / "scripts" / "ci" / "resolve-mapping.py")


@pytest.fixture(scope="session")
def apply_doc_patch_module(repo_root):
    return _load_script_module("apply_doc_patch", repo_root / "scripts" / "ci" / "apply-doc-patch.py")


@pytest.fixture(scope="session")
def fix_deps_module(repo_root):
    return _load_script_module("fix_deps", repo_root / "scripts" / "fix_deps.py")


@pytest.fixture(scope="session")
def create_stubs_module(repo_root):
    return _load_script_module("create_stubs", repo_root / "scripts" / "create_stubs.py")


@pytest.fixture(scope="session")
def patch_drive_linux_calendar_module(repo_root):
    return _load_script_module(
        "patch_drive_linux_calendar", repo_root / "scripts" / "patch_drive_linux_calendar.py"
    )


@pytest.fixture(scope="session")
def patch_drive_linux_panel_module(repo_root):
    return _load_script_module(
        "patch_drive_linux_panel", repo_root / "scripts" / "patch_drive_linux_panel.py"
    )


@pytest.fixture(scope="session")
def patch_drive_linux_drawer_module(repo_root):
    return _load_script_module(
        "patch_drive_linux_drawer", repo_root / "scripts" / "patch_drive_linux_drawer.py"
    )


@pytest.fixture(scope="session")
def patch_drive_linux_sync_bridge_module(repo_root):
    return _load_script_module(
        "patch_drive_linux_sync_bridge", repo_root / "scripts" / "patch_drive_linux_sync_bridge.py"
    )


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
