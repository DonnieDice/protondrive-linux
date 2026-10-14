"""Transient installer cleanup must preserve the persistent guest disk."""
from pathlib import Path
import re


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ci/vm-provision/el10-install.sh"


def test_transient_undefine_never_removes_guest_storage():
    source = SCRIPT.read_text()
    commands = re.findall(r"sudo virsh undefine[^;\n\"]+", source)
    assert commands
    for command in commands:
        assert "--remove-all-storage" not in command
        assert "--storage" not in command
        assert "--wipe-storage" not in command
        assert "--nvram" in command


def test_persistent_definition_failure_still_stops_provisioning():
    source = SCRIPT.read_text()
    assert 'grep -qx "$TRANSIENT"' in source
    assert 'die "transient domain $TRANSIENT could not be removed; pre-existing state blocks define"' in source
