"""Unit tests for the canonical VM/distro matrix (tests/robot/vars/vms.py).

Guards against config regressions: every distro must have a reachable-looking
IP, a known install family, a non-empty artifact glob, unique IPs, and a 1:1
correspondence with the per-distro install/transfer/vmtest scripts and workflow
files.
"""

import pathlib

import pytest
import vms  # noqa: E402  (path injected by conftest)

REPO = pathlib.Path(__file__).resolve().parents[2]
VALID_FAMILIES = {"apk", "deb", "rpm-dnf", "rpm-zypper", "aur"}

PER_DISTRO_SCRIPTS = ("install", "transfer", "vmtest")
PER_DISTRO_WORKFLOWS = ("install", "transfer", "vmtest")


def test_matrix_is_nonempty():
    assert len(vms.VMS) == 10, "expected all 10 target distros"


@pytest.mark.parametrize("distro,cfg", vms.VMS.items())
def test_entry_shape(distro, cfg):
    assert cfg["ip"].startswith("192.168.1."), f"{distro}: IP not on the VM subnet"
    assert cfg["family"] in VALID_FAMILIES, f"{distro}: unknown family {cfg['family']}"
    assert cfg["glob"], f"{distro}: empty artifact glob"


def test_ips_are_unique():
    ips = [c["ip"] for c in vms.VMS.values()]
    assert len(ips) == len(set(ips)), "duplicate VM IPs in matrix"


@pytest.mark.parametrize("distro", vms.VMS.keys())
def test_has_matching_install_script(distro):
    p = REPO / "scripts" / "ci" / "install" / distro / "install.sh"
    assert p.is_file(), f"missing install script for {distro}: {p}"


@pytest.mark.parametrize("distro", vms.VMS.keys())
def test_has_matching_transfer_script(distro):
    p = REPO / "scripts" / "ci" / "transfer" / distro / "transfer.sh"
    assert p.is_file(), f"missing transfer script for {distro}: {p}"


@pytest.mark.parametrize("distro", vms.VMS.keys())
def test_has_matching_vmtest_script(distro):
    p = REPO / "scripts" / "ci" / "vmtest" / distro / "test.sh"
    assert p.is_file(), f"missing vmtest script for {distro}: {p}"


@pytest.mark.parametrize("stage", PER_DISTRO_WORKFLOWS)
@pytest.mark.parametrize("distro", vms.VMS.keys())
def test_has_matching_workflow(distro, stage):
    p = REPO / ".gitlab" / "workflows" / stage / f"{distro}.yml"
    assert p.is_file(), f"missing {stage} workflow for {distro}: {p}"


def test_get_variables_hook():
    v = vms.get_variables("debian-12")
    assert v["VM_IP"] == "192.168.1.162"
    assert v["PKG_FAMILY"] == "deb"
    assert v["DISTRO"] == "debian-12"
