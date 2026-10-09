#!/usr/bin/env bash
# scripts/ci/vm-provision/alpine-320-verify.sh
#
# Acceptance verification + authorized repair for the alpine320 guest
# (issue #21, parent #5). Complements alpine-320-install.sh: job 26864
# completed the install (Alpine 3.20 on the qcow2, br0 NIC, sshd listening at
# 192.168.1.157) but authorized the STALE mounted .pub sidecar instead of the
# public half of the private key the runner offers, so the SSH probe was
# rejected (Permission denied, publickey).
#
# This job:
#   1. records read-only guest state (domstate, dumpxml facts, disk info)
#   2. derives the correct public key from the runner's private key
#   3. repairs /root/.ssh/authorized_keys INSIDE THE alpine320 GUEST ONLY,
#      through the qemu-guest-agent channel (virsh qemu-agent-command
#      guest-exec) - no console login, no reinstall, no other guest touched
#   4. diagnoses sshd (service status, PermitRootLogin, PubkeyAuthentication,
#      AuthorizedKeysFile, file permissions) and ensures sshd is enabled +
#      running before the probe
#   5. proves acceptance: SSH publickey probe from the runner, in-guest
#      service status, IP config, guest-ping
#
# Mutations are confined to the alpine320 guest: starting it when shut off
# (issue #21 requires it reachable) and the contents of
# /root/.ssh/authorized_keys inside it (issue #21 scope step 4: "Hermes public
# key added for the appropriate user"). Nothing else is written anywhere.
# The private key never leaves the runner; only fingerprints are printed.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-alpine320}"
VM_IP="${VM_IP:-192.168.1.157}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/alpine320/vdisk1.qcow2}"
OUT_DIR="${PROVISION_OUT_DIR:-verify-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
log()  { echo "[verify] $*"; }
die()  { echo "FATAL: $*" >&2; exit 1; }

PRIV=/root/.ssh/id_ed25519

# ------------------------------------------------------------- read-only ----
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || die "cannot reach tower"

STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
log "persistent guest state: ${STATE:-unknown}"
if [ "$STATE" != "running" ]; then
  log "guest not running - starting it (authorized: acceptance requires reachable guest)"
  tower "sudo virsh start '$GUEST'" || die "guest failed to start"
  sleep 20
fi
STATE="$(tower "sudo virsh domstate '$GUEST'" 2>/dev/null)"
[ "$STATE" = "running" ] || die "guest is not running (state: $STATE)"
echo "state: $STATE" > "$OUT_DIR/guest-state.txt"

{
  echo "=== virsh dumpxml (key facts) ==="
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source bridge=|<mac |<channel|guest_agent|<serial|<console" || true
  echo "=== qemu-img info ==="
  tower "sudo qemu-img info '$DISK_PATH'"
  echo "=== ping occupancy (from tower) ==="
  tower "ping -c1 -W2 '$VM_IP' >/dev/null 2>&1 && echo 'PING: answers' || echo 'PING: silent'"
} | tee "$OUT_DIR/guest-facts.txt"

# ------------------------------------------------------------- agent check --
log "probing qemu-guest-agent (guest-ping)"
AG_OK=0
for i in $(seq 1 24); do
  if tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" >/dev/null 2>&1; then
    AG_OK=1; break
  fi
  log "agent not answering yet (attempt $i/24)"; sleep 10
done
[ "$AG_OK" = "1" ] || die "qemu-guest-agent not answering: run vm:provision:alpine320 (fixed script) to reinstall"
echo "guest-ping: answered" | tee -a "$OUT_DIR/guest-state.txt"
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}''" 2>/dev/null \
  | tee -a "$OUT_DIR/guest-state.txt" || true

# agent_exec <shell command> -> echoes decoded stdout; sets AGENT_RC
agent_exec() {
  local cmd="$1" payload resp pid st ec out
  payload="$(jq -nc --arg cmd "$cmd" '{execute:"guest-exec",arguments:{path:"sh",arg:["-c",$cmd],"capture-output":true}}')"
  resp="$(tower "sudo virsh qemu-agent-command '$GUEST' '$payload'")" \
    || { AGENT_RC=255; return 1; }
  pid="$(jq -r '.return.pid // empty' <<<"$resp")"
  [ -n "$pid" ] || { AGENT_RC=255; return 1; }
  for _ in $(seq 1 30); do
    st="$(tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}'")"
    if [ "$(jq -r '.return.exited // false' <<<"$st")" = "true" ]; then
      ec="$(jq -r '.return.exitcode // 255' <<<"$st")"
      out="$(jq -r '.return."out-data" // ""' <<<"$st" | base64 -d)"
      AGENT_RC="$ec"
      printf '%s' "$out"
      return 0
    fi
    sleep 2
  done
  AGENT_RC=254; return 1
}

# ------------------------------------------------------------- key repair --
[ -r "$PRIV" ] || die "no workforce private key at $PRIV (SSH_PRIVATE_KEY_B64 absent; cannot authorize a key the runner can offer)"
DERIVED_PUB="$(ssh-keygen -y -f "$PRIV")" || die "cannot derive public half of the workforce key"
DERIVED_FP="$(ssh-keygen -lf "$PRIV" | awk '{print $2}')"
log "correct authorized key (derived from runner private half): $DERIVED_FP"

GUEST_KEYS="$(agent_exec "cat /root/.ssh/authorized_keys 2>/dev/null")"; AGENT_RC="${AGENT_RC:-255}"
printf '%s\n' "$GUEST_KEYS" > "$OUT_DIR/guest-authorized-keys-before.txt"
GUEST_FP="$(printf '%s\n' "$GUEST_KEYS" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')"
log "guest authorized key before repair: ${GUEST_FP:-none}"

if printf '%s\n' "$GUEST_KEYS" | grep -qF "$DERIVED_PUB"; then
  log "guest already authorizes the correct key - no repair needed"
  echo "repair: none needed" > "$OUT_DIR/key-repair.txt"
else
  log "guest authorized key differs - repairing through the guest agent (issue #21 scope step 4)"
  B64="$(printf '%s\n' "$DERIVED_PUB" | base64 -w0)"
  agent_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo '$B64' | base64 -d > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && echo KEY_REPAIR_OK" \
    > "$OUT_DIR/key-repair.txt" || true
  cat "$OUT_DIR/key-repair.txt"
  grep -q KEY_REPAIR_OK "$OUT_DIR/key-repair.txt" || die "authorized_keys repair through the agent failed"
  # verify the write from inside the guest
  GUEST_KEYS2="$(agent_exec "cat /root/.ssh/authorized_keys")"
  printf '%s\n' "$GUEST_KEYS2" > "$OUT_DIR/guest-authorized-keys-after.txt"
  printf '%s\n' "$GUEST_KEYS2" | grep -qF "$DERIVED_PUB" || die "authorized_keys still wrong after repair"
  log "repair verified from inside the guest"
fi
echo "derived key fingerprint: $DERIVED_FP" >> "$OUT_DIR/key-repair.txt"

# ------------------------------------------------------------- sshd diagnosis --
log "diagnosing sshd inside the alpine320 guest"
{
  echo "=== rc-service sshd status ==="
  agent_exec "rc-service sshd status 2>&1 || true"
  echo "=== sshd process ==="
  agent_exec "ps aux 2>/dev/null | grep sshd | grep -v grep || echo 'no sshd process found'"
  echo "=== sshd_config key directives ==="
  agent_exec "grep -E '^(PubkeyAuthentication|PermitRootLogin|AuthorizedKeysFile|PasswordAuthentication|UsePAM|KbdInteractiveAuthentication)' /etc/ssh/sshd_config 2>/dev/null || echo 'sshd_config missing or no matching directives'"
  echo "=== /root/.ssh permissions ==="
  agent_exec "ls -lad /root/.ssh 2>/dev/null && ls -la /root/.ssh/ 2>/dev/null || echo '/root/.ssh not found'"
  echo "=== /root permissions ==="
  agent_exec "ls -ld /root"
  echo "=== authorized_keys content type ==="
  agent_exec "wc -l /root/.ssh/authorized_keys 2>/dev/null; file /root/.ssh/authorized_keys 2>/dev/null || true; head -c 40 /root/.ssh/authorized_keys 2>/dev/null; echo"
} | tee "$OUT_DIR/sshd-diag.txt" || true

# Ensure sshd is enabled at boot and started
log "ensuring sshd is enabled and running"
agent_exec "rc-update add sshd default 2>&1 || true" >> "$OUT_DIR/sshd-diag.txt"
agent_exec "rc-service sshd start 2>&1 || echo 'sshd start returned non-zero'" >> "$OUT_DIR/sshd-diag.txt"
sleep 3
# Re-check sshd status after start attempt
agent_exec "rc-service sshd status 2>&1 || true" >> "$OUT_DIR/sshd-diag.txt" || true
# Also check if sshd is actually listening
agent_exec "ss -tlnp 2>/dev/null | grep ':22' || netstat -tlnp 2>/dev/null | grep ':22 ' || echo 'no listener on :22 found'" >> "$OUT_DIR/sshd-diag.txt" || true

# ------------------------------------------------------------- ssh probe ----
log "waiting for TCP/22 at $VM_IP (up to 120s)"
up=0
for i in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 2
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

log "SSH probe from the runner (publickey only, exact authorized identity)"
ssh $SSH_OPTS -o IdentitiesOnly=yes -i "$PRIV" -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; cat /etc/alpine-release" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting in-guest acceptance evidence"
ssh $SSH_OPTS -o IdentitiesOnly=yes -i "$PRIV" "root@$VM_IP" \
  "rc-service qemu-guest-agent status; rc-service sshd status; rc-update show default; ip -4 addr show eth0; grep -c ssh-ed25519 /root/.ssh/authorized_keys" \
  | tee -a "$OUT_DIR/ssh-probe.txt" || die "in-guest verification failed"

{
  echo "=== guest agent ping (virsh) ==="
  tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" && echo "guest-ping ok"
  echo "=== authorized key fingerprint in guest ==="
  ssh $SSH_OPTS -o IdentitiesOnly=yes -i "$PRIV" "root@$VM_IP" \
    "ssh-keygen -lf /root/.ssh/authorized_keys 2>/dev/null | awk '{print \$1, \$2}'"
} | tee -a "$OUT_DIR/ssh-probe.txt" || true

log "=== verification complete ==="
exit 0
