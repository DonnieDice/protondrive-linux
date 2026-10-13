"""Guard the read-only guest diagnostic against the observed SSH outage."""
from pathlib import Path
import re


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ci/vm-provision/alpine-322-diag.sh"


def test_diagnostic_never_stops_or_restarts_guest_ssh():
    commands = re.findall(r'^agent_exec "(.*)"', SCRIPT.read_text(), re.MULTILINE)
    assert commands
    for command in commands:
        assert not re.search(r'\b(?:pkill|killall|kill|chpasswd|passwd|usermod)\b', command)
        assert not re.search(r'rc-service\s+sshd\s+(?:start|stop|restart|reload|zap)', command)
        assert not re.search(r'/usr/sbin/sshd\s+-d', command)


def test_diagnostic_reports_fingerprints_not_authorized_key_contents():
    source = SCRIPT.read_text()
    assert "cat /root/.ssh/authorized_keys" not in source
    assert "keyprefix=" not in source
    assert "ssh-keygen -lf /root/.ssh/authorized_keys" in source


def test_diagnostic_reports_locked_account_without_shadow_contents():
    source = SCRIPT.read_text()
    assert "root_password_state=locked" in source
    assert not re.search(r'cat\s+/etc/shadow', source)
