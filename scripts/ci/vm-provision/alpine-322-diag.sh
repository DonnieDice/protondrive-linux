#!/bin/bash
# scripts/ci/vm-provision/alpine-322-diag.sh
#
# Read-only in-guest SSH/auth diagnosis for the alpine322 guest (issue #22,
# parent #6). Repeated vm:provision:alpine322 runs install end-to-end
# (INSTALL_DONE, CHROOT_RC=0, network + sshd up) but the runner-side SSH
# probe is rejected with "Permission denied (publickey,...)". This script
# pulls the decisive evidence from inside the RUNNING guest via the QEMU
# guest agent (channel present in the domain; qemu-guest-agent installed by
# the chroot config), without re-running the ~45 minute install:
#   - sshd effective config (sshd -T): authorizedkeysfile / pubkeyaccepted* /
#     permitrootlogin / passwordauthentication / strictmodes
#   - /root, /root/.ssh, /root/.ssh/authorized_keys ownership + mode
#     (StrictModes rejects the key if any ancestor is group/world-writable)
#   - authorized_keys content fingerprint vs the runner's mounted key
#   - sshd log output (auth.reject lines) captured while a live probe runs
#
# guest-exec runs the command asynchronously; we poll guest-exec-status for
# the captured stdout. Strictly read-only inside the guest.
set -euo pipefail

log() { echo "[diag] $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }

GUEST="alpine322"
VM_IP="192.168.1.126"
OUT_DIR="provision-results"
mkdir -p "$OUT_DIR"
DIAG="$OUT_DIR/in-guest-diag.txt"
: >"$DIAG"

tower() { ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_KNOWN_HOSTS" tower "$@"; }

[ "$(tower "sudo virsh domstate '$GUEST' 2>/dev/null")" = "running" ] ||
  die "guest $GUEST is not running - nothing to diagnose (boot the prior provision first)"

log "guest-agent ping"
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" | tee -a "$DIAG" ||
  die "qemu guest agent not responding; cannot diagnose in-guest"

# run a shell command in the guest, capture stdout+stderr+exitcode
guest_exec() {
  local script="$1"
  local cmd_payload resp pid status out err
  cmd_payload=$(python3 - "$script" <<'PYEOF'
import json, sys, base64
script = sys.argv[1]
b64 = base64.b64encode(script.encode()).decode()
print(json.dumps({"execute": "guest-exec", "arguments": {
    "path": "/bin/sh",
    "arg": ["-c", script],
    "capture-output": True}}))
PYEOF
)
  resp=$(tower "sudo virsh qemu-agent-command '$GUEST' '$cmd_payload'")
  pid=$(echo "$resp" | python3 -c "import json,sys;print(json.load(sys.stdin)['return']['pid'])")
  sleep 3
  for _ in 1 2 3 4 5; do
    status=$(tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}'")
    if echo "$status" | grep -q '"exited":true'; then break; fi
    sleep 2
  done
  python3 - "$status" <<'PYEOF'
import json, sys, base64
d = json.loads(sys.argv[1])['return']
if not d.get('exited'):
    print("[diag] WARN: guest-exec did not exit within budget")
out = d.get('out-data')
if out: sys.stdout.write(base64.b64decode(out).decode(errors='replace'))
err = d.get('err-data')
if err: sys.stderr.write(base64.b64decode(err).decode(errors='replace'))
print(f"[diag] guest exitcode={d.get('exitcode')}")
PYEOF
}

log "=== sshd effective config ===" | tee -a "$DIAG"
guest_exec "/usr/sbin/sshd -T 2>&1 | grep -Ei 'permitrootlogin|pubkeyaccepted|authorizedkeysfile|passwordauthentication|strictmodes|usepam|allowusers|denygroups|pubkeyauth|kbfinteractive|challengeresponse|authenticationmethods|hostkey'" | tee -a "$DIAG"

log "=== root home + key perms (StrictModes) ===" | tee -a "$DIAG"
guest_exec "ls -ld /root /root/.ssh /root/.ssh/authorized_keys 2>&1; stat -c '%a %U:%G %n' /root /root/.ssh /root/.ssh/authorized_keys 2>&1" | tee -a "$DIAG"

log "=== authorized_keys content ===" | tee -a "$DIAG"
guest_exec "cat /root/.ssh/authorized_keys 2>&1; echo '---fingerprints---'; awk '{print \$1\" \"\$2}' /root/.ssh/authorized_keys | while read t k; do echo \"type=\$t keyprefix=\${k:0:40}...\"; done" | tee -a "$DIAG"

log "=== sshd_config non-comment lines ===" | tee -a "$DIAG"
guest_exec "grep -Ev '^[[:space:]]*(#|\$)' /etc/ssh/sshd_config 2>&1; echo '--- include dir ---'; ls -la /etc/ssh/sshd_config.d 2>&1; for f in /etc/ssh/sshd_config.d/*; do [ -f \"\$f\" ] && { echo \"--- \$f ---\"; cat \"\$f\"; }; done" | tee -a "$DIAG"

log "=== sshd foreground debug (one-shot) ===" | tee -a "$DIAG"
guest_exec "pkill sshd; /usr/sbin/sshd -d -e >/tmp/sshd-d.log 2>&1 & sleep 1; /usr/sbin/sshd >/dev/null 2>&1 & sleep 6; pkill sshd; grep -Ei 'auth|key|denied|user|pubkey' /tmp/sshd-d.log | tail -40" | tee -a "$DIAG"

log "=== restarting sshd and one verbose probe from runner ===" | tee -a "$DIAG"
VM_KEY_TMP="$(mktemp)"
cp /root/.ssh/id_ed25519 "$VM_KEY_TMP"
sed -i 's/\r$//' "$VM_KEY_TMP"
[ -n "$(tail -c1 "$VM_KEY_TMP" 2>/dev/null)" ] && printf '\n' >>"$VM_KEY_TMP"
chmod 600 "$VM_KEY_TMP"
ssh -vvv -F /dev/null -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_KNOWN_HOSTS" -i "$VM_KEY_TMP" -o IdentitiesOnly=yes "root@$VM_IP" "echo PROBE_OK; hostname" >"$OUT_DIR/ssh-probe-vvv.txt" 2>&1 || true
rm -f "$VM_KEY_TMP"
grep -Ei 'offering|publickey|server accepts|Authentications|denied|sign|identity|expecting|host key' "$OUT_DIR/ssh-probe-vvv.txt" | tail -40 | tee -a "$DIAG"

log "=== diag complete: evidence in provision-results ==="
exit 0
