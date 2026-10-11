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

GUEST="${GUEST:-alpine322}"
VM_IP="${VM_IP:-192.168.1.126}"
OUT_DIR="${PROVISION_OUT_DIR:-provision-results}"
mkdir -p "$OUT_DIR"
DIAG="$OUT_DIR/in-guest-diag.txt"
: >"$DIAG"

PRIV="/root/.ssh/id_ed25519"
PAYLOAD_TMPF="/tmp/hermes-alpine322-payload.$$.json"
cleanup_payload() {
  ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_KNOWN_HOSTS" tower "rm -f '$PAYLOAD_TMPF'" >/dev/null 2>&1 || true
}
trap cleanup_payload EXIT

tower() { ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_KNOWN_HOSTS" tower "$@"; }

[ "$(tower "sudo virsh domstate '$GUEST' 2>/dev/null")" = "running" ] ||
  die "guest $GUEST is not running - nothing to diagnose (boot the prior provision first)"

log "guest-agent ping"
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" | tee -a "$DIAG" ||
  die "qemu guest agent not responding; cannot diagnose in-guest"

# agent_exec <shell command> -> echoes decoded stdout; sets AGENT_RC
#
# Transport-safety: the JSON payload never appears inside the ssh command
# string. It is piped to a temp file on tower, and virsh receives it through
# remote command substitution - "$(cat file)" - which passes the file's bytes
# as one argument verbatim, immune to quotes/parens/metacharacters in guest
# commands. This was the failure mode of job 45002 (issue #21): the payload
# was embedded in single quotes, so guest commands containing single quotes
# (the sshd greps) broke tower's remote shell. Temp file removed on every
# exit path (trap). Payloads carry only diagnostic shell text for the guest;
# no key material ever crosses the transport.
agent_exec() {
  local cmd="$1" payload resp pid status out err
  payload=$(python3 - "$cmd" <<'PYEOF'
import json, sys, base64
script = sys.argv[1]
b64 = base64.b64encode(script.encode()).decode()
print(json.dumps({"execute": "guest-exec", "arguments": {
    "path": "/bin/sh",
    "arg": ["-c", script],
    "capture-output": True}}))
PYEOF
)
  printf '%s' "$payload" | tower "cat > '$PAYLOAD_TMPF'" ||
    { AGENT_RC=255; return 1; }
  resp=$(tower "sudo virsh qemu-agent-command '$GUEST' \"\$(cat '$PAYLOAD_TMPF')\" && rm -f '$PAYLOAD_TMPF'") ||
    { AGENT_RC=255; tower "rm -f '$PAYLOAD_TMPF'" >/dev/null 2>&1 || true; return 1; }
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

log "=== sshd effective config (sshd -T) ===" | tee -a "$DIAG"
agent_exec "sshd -T 2>&1 | grep -iE '^(permitrootlogin|pubkeyauthentication|authorizedkeysfile|pubkeyacceptedalgorithms|strictmodes|allowusers|denyusers|passwordauthentication|usepam|hostkey)'" | tee -a "$DIAG" || true

log "=== sshd_config Include directives ===" | tee -a "$DIAG"
agent_exec "grep -i '^Include' /etc/ssh/sshd_config 2>/dev/null; ls /etc/ssh/sshd_config.d/ 2>/dev/null; cat /etc/ssh/sshd_config.d/*.conf 2>/dev/null || echo 'no sshd_config.d contents'" | tee -a "$DIAG" || true

log "=== root home + key perms (StrictModes) ===" | tee -a "$DIAG"
agent_exec "ls -ld /root /root/.ssh /root/.ssh/authorized_keys 2>&1; stat -c '%a %U:%G %n' /root /root/.ssh /root/.ssh/authorized_keys 2>&1" | tee -a "$DIAG"

log "=== authorized_keys content + fingerprint ===" | tee -a "$DIAG"
agent_exec "cat /root/.ssh/authorized_keys 2>&1; echo '---fingerprints---'; awk '{print \$1\" \"\$2}' /root/.ssh/authorized_keys | while read t k; do echo \"type=\$t keyprefix=\${k:0:40}...\"; done" | tee -a "$DIAG"

log "=== sshd_config non-comment lines ===" | tee -a "$DIAG"
agent_exec "grep -Ev '^[[:space:]]*(#|\$)' /etc/ssh/sshd_config 2>&1; echo '--- include dir ---'; ls -la /etc/ssh/sshd_config.d 2>&1; for f in /etc/ssh/sshd_config.d/*; do [ -f \"\$f\" ] && { echo \"--- \$f ---\"; cat \"\$f\"; }; done" | tee -a "$DIAG" || true

log "=== sshd foreground debug (one-shot) ===" | tee -a "$DIAG"
agent_exec "pkill sshd; /usr/sbin/sshd -d -e >/tmp/sshd-d.log 2>&1 & sleep 1; /usr/sbin/sshd >/dev/null 2>&1 & sleep 6; pkill sshd; grep -Ei 'auth|key|denied|user|pubkey' /tmp/sshd-d.log | tail -40" | tee -a "$DIAG" || true

log "=== restarting sshd and one verbose probe from runner ===" | tee -a "$DIAG"
VM_KEY_TMP="$(mktemp)"
cp "$PRIV" "$VM_KEY_TMP"
sed -i 's/\r$//' "$VM_KEY_TMP"
[ -n "$(tail -c1 "$VM_KEY_TMP" 2>/dev/null)" ] && printf '\n' >>"$VM_KEY_TMP"
chmod 600 "$VM_KEY_TMP"
ssh -vvv -F /dev/null -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_KNOWN_HOSTS" -i "$VM_KEY_TMP" -o IdentitiesOnly=yes "root@$VM_IP" "echo PROBE_OK; hostname" >"$OUT_DIR/ssh-probe-vvv.txt" 2>&1 || true
rm -f "$VM_KEY_TMP"
grep -Ei 'offering|publickey|server accepts|Authentications|denied|sign|identity|expecting|host key' "$OUT_DIR/ssh-probe-vvv.txt" | tail -40 | tee -a "$DIAG"

log "=== diag complete: evidence in provision-results ==="
exit 0
