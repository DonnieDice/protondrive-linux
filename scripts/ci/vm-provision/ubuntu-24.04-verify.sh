#!/usr/bin/env bash
# scripts/ci/vm-provision/ubuntu-24.04-verify.sh
#
# Acceptance verification + authorized repair for the ubuntu2404 guest
# (issue #24, parent #7). Complements ubuntu-24.04-install.sh: the install
# job may have completed the OS install (qcow2 + br0 + sshd listening at
# 192.168.1.219) but the key probe may have been rejected because the
# authorized key in the guest differs from the public half of the private key
# the runner offers.
#
# This job:
#   1. records read-only guest state (domstate, dumpxml facts, disk info)
#   2. derives the correct public key from the runner's private key
#   3. repairs /root/.ssh/authorized_keys INSIDE THE ubuntu2404 GUEST ONLY,
#      through the qemu-guest-agent channel (virsh qemu-agent-command
#      guest-exec) - no console login, no reinstall, no other guest touched
#   4. proves acceptance: SSH publickey probe from the runner, in-guest
#      service status, IP config, guest-ping, qemu-img info
#
# Mutations are confined to the ubuntu2404 guest: starting it when shut off
# (issue #24 requires it reachable) and the contents of
# /root/.ssh/authorized_keys inside it (issue #24 scope step 4: "Hermes key
# authorized for login"). Nothing else is written anywhere.
# The private key never leaves the runner; only fingerprints are printed.
set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
GUEST="${GUEST:-ubuntu2404}"
VM_IP="${VM_IP:-192.168.1.219}"
DISK_PATH="${DISK_PATH:-/mnt/pool_two/domains/ubuntu2404/vdisk1.qcow2}"
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
  tower "sudo virsh dumpxml '$GUEST'" | grep -E "<name>|<uuid>|<source file=|<source bridge=|<source network=|<mac |<channel|guest_agent|<serial|<console|<loader|<nvram|<interface" || true
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
[ "$AG_OK" = "1" ] || die "qemu-guest-agent not answering: run vm:provision:ubuntu2404 to reinstall"
echo "guest-ping: answered" | tee -a "$OUT_DIR/guest-state.txt"
tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" 2>/dev/null \
  | tee -a "$OUT_DIR/guest-state.txt" || true

# agent_exec <shell command> -> echoes decoded stdout; sets AGENT_RC
agent_exec() {
  local cmd="$1" payload resp pid st ec out
  payload="$(jq -nc --arg cmd "$cmd" '{execute:"guest-exec",arguments:{path:"sh",arg:["-c",$cmd],capture-output:true}}')"
  resp="$(tower "sudo virsh qemu-agent-command '$GUEST' '$payload'")" \
    || { AGENT_RC=255; return 1; }
  pid="$(jq -r '.return.pid // empty' <<<"$resp")"
  [ -n "$pid" ] || { AGENT_RC=255; return 1; }
  for _ in $(seq 1 30); do
    st="$(tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}'")
"
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

# ------------------------------------------------------------- key repair ---
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
  log "guest authorized key differs - repairing through the guest agent (issue #24 scope step 4)"
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

# ------------------------------------------------------------- ssh probe ---
log "waiting for TCP/22 at $VM_IP (up to 120s)"
up=0
for i in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/$VM_IP/22") 2>/dev/null; then up=1; exec 3>&-; break; fi
  sleep 2
done
[ "$up" = "1" ] || die "sshd never came up at $VM_IP"

log "SSH probe from the runner (publickey only, exact authorized identity)"
ssh $SSH_OPTS -o IdentitiesOnly=yes -i "$PRIV" -o ConnectTimeout=15 "root@$VM_IP" \
  "hostname; whoami; uname -a; lsb_release -a 2>/dev/null || cat /etc/os-release | head -5" | tee "$OUT_DIR/ssh-probe.txt" \
  || die "SSH probe failed"

log "collecting in-guest acceptance evidence"
ssh $SSH_OPTS -o IdentitiesOnly=yes -i "$PRIV" "root@$VM_IP" \
  "systemctl is-active ssh qemu-guest-agent; systemctl is-enabled ssh qemu-guest-agent; ip -4 addr show eth0; grep -c ssh-ed25519 /root/.ssh/authorized_keys; dpkg -l qemu-guest-agent openssh-server 2>/dev/null | grep '^ii'; systemctl status qemu-guest-agent --no-pager 2>&1 | head -5" \
  | tee -a "$OUT_DIR/ssh-probe.txt" || die "in-guest verification failed"

{
  echo "=== guest agent ping (virsh) ==="
  tower "sudo virsh qemu-agent-command '$GUEST' '{\"execute\":\"guest-ping\"}'" && echo "guest-ping ok"
  echo "=== authorized key fingerprint in guest ==="
  ssh $SSH_OPTS -o IdentitiesOnly=yes -i "$PRIV" "root@$VM_IP" \
    "ssh-keygen -lf /root/.ssh/authorized_keys 2>/dev/null | awk '{print \$1, \$2}'"
  echo "=== ubuntu-24.04 CI transport smoke ==="
  ssh $SSH_OPTS -o IdentitiesOnly=yes -i "$PRIV" "root@$VM_IP" \
    "dpkg -l | grep -E 'qemu-guest-agent|openssh-server'; echo '---'; cat /etc/ssh/sshd_config | grep PermitRootLogin"
} | tee -a "$OUT_DIR/ssh-probe.txt" || true

log "=== verification complete ==="
exit 0
