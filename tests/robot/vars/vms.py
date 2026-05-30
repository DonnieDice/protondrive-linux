"""Canonical test-VM matrix for protondrive-linux acceptance testing.

Single source of truth for which built artifact maps to which target VM and how
it is installed. Imported by the pytest acceptance helpers and consumable by the
Robot runner / CI (see tests/README.md). Keep in sync with
.gitlab/workflows/verify/<distro>.yml and scripts/ci/deploy/<distro>/.
"""

# distro key -> {ip, family, glob}
#   family drives the install command (apk|deb|rpm-dnf|rpm-zypper|aur)
#   glob   matches the artifact in artifacts/ produced by the build stage
VMS = {
    "alpine-3.20":          {"ip": "192.168.1.157", "family": "apk",        "glob": "proton-drive_*_alpine320_amd64.apk.tar.gz"},
    "alpine-3.22":          {"ip": "192.168.1.126", "family": "apk",        "glob": "proton-drive_*_alpine322_amd64.apk.tar.gz"},
    "debian-12":            {"ip": "192.168.1.162", "family": "deb",        "glob": "proton-drive_*_debian12_*.deb"},
    "debian-13":            {"ip": "192.168.1.120", "family": "deb",        "glob": "proton-drive_*_debian13_*.deb"},
    "ubuntu-24.04":         {"ip": "192.168.1.219", "family": "deb",        "glob": "proton-drive_*_ubuntu2404_*.deb"},
    "ubuntu-26.04":         {"ip": "192.168.1.168", "family": "deb",        "glob": "proton-drive_*_ubuntu2604_*.deb"},
    "el10":                 {"ip": "192.168.1.123", "family": "rpm-dnf",    "glob": "*.rpm"},
    "fedora-43":            {"ip": "192.168.1.183", "family": "rpm-dnf",    "glob": "*.rpm"},
    "opensuse-tumbleweed":  {"ip": "192.168.1.245", "family": "rpm-zypper", "glob": "*.rpm"},
    "arch":                 {"ip": "192.168.1.128", "family": "aur",        "glob": "*.pkg.tar.zst"},
}


def get_variables(distro=None):
    """Robot variable-file hook. `robot --variablefile vms.py:debian-12` injects
    ${VM_IP}/${PKG_FAMILY}/${PKG_GLOB} for that distro."""
    if distro and distro in VMS:
        v = VMS[distro]
        return {"VM_IP": v["ip"], "PKG_FAMILY": v["family"], "PKG_GLOB": v["glob"], "DISTRO": distro}
    return {"VMS": VMS}
