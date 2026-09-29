#!/usr/bin/env bash
# scripts/ci/vm-provision/repair-vm-network.sh
#
# Authorized network repair for issue #14 scope item 2: "If VM state must be
# inspected or repaired, use the deployment host-ssh skill profile ... authorized
# host operations limited to what this assignment requires (e.g. start the
# debian13 guest)". The guests boot the installed OS (domblk repair job 26734)
# with a connected qemu guest-agent, but enp1s0 never acquires its documented
# IPv4 (debian13 192.168.1.120 / debian12 192.168.1.162) and neither MAC
# appears in the tower br0 ARP table (read-only diag job 26943, issue #15 note
# 12804). Without the guest network, vm:provision:build-deps and
# vm:verify:rust-toolchain cannot run — the routed execution dependency of
# parent #3.
#
# Transport: the runner-mounted /root/.ssh config (alias: tower) — the same
# transport used by jobs 24251, 25655, 26734, and 26943.
#
# Mutations, performed ONLY through the connected guest-agent channel and ONLY
# on the two in-scope guests (debian13 first, then debian12 which the shared
# provisioning job also needs):
#   1. Read-only diagnosis of the guest network via guest-exec (ip addr show,
#      ip route, nmcli/ifup status as available).
#   2. Least-invasive first: request a DHCP lease on the primary interface
#      (renewal / interface bounce) via guest-exec.
#   3. If DHCP still yields no IPv4: assign the documented static IPv4 for the
#      guest (192.168.1.120/24 for debian13, 192.168.1.162/24 for debian12,
#      gateway 192.168.1.1) via guest-exec, with evidence recorded before/after.
# All commands run inside the guest as root via the agent channel; no domain
# XML, disk, or host networking is touched. Read-only state evidence
# (virsh domifaddr, ip neigh) is recorded before and after.

set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
OUT_DIR="${REPAIR_NET_OUT_DIR:-net-repair-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: >"$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

echo "=== [net-repair] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || {
  echo "FATAL: cannot reach tower"
  exit 1
}

# guest_exec <guest> <command...>  — run a command in the guest as root through
# the connected qemu guest-agent channel; prints stdout; returns the command's
# exit code. Uses guest-exec + poll of the returned pid, base64 to move the
# payload safely through the JSON + shell layers.
guest_exec() {
  local guest="$1"
  shift
  local cmd_b64 rc out_b64 out
  cmd_b64="$(printf '%s' "$*" | base64 -w0)"
  local pid
  pid="$(tower "sudo virsh qemu-agent-command '$guest' \"{\\\"execute\\\":\\\"guest-exec\\\",\\\"arguments\\\":{\\\"path\\\":\\\"/bin/sh\\\",\\\"arg\\\":[\\\"-c\\\",\\\"\\$(echo $cmd_b64 | base64 -d)\\\"],\\\"capture-output\\\":true}}\" 2>/dev/null" | grep -oE '"return": \{"pid":[0-9]+' | grep -oE '[0-9]+')"
  if [ -z "$pid" ]; then
    echo "GUEST_EXEC_FAIL: no pid returned (agent not connected?)"
    return 1
  fi
  local i=0
  while [ "$i" -lt 60 ]; do
    out="$(tower "sudo virsh qemu-agent-command '$guest' \"{\\\"execute\\\":\\\"guest-exec-status\\\",\\\"arguments\\\":{\\\"pid\\\":$pid}}\" 2>/dev/null")"
    if echo "$out" | grep -q '"exited": true'; then
      rc="$(echo "$out" | grep -oE '"exitcode": ?[0-9]+' | grep -oE '[0-9]+')"
      out_b64="$(echo "$out" | grep -oE '"out-data\": ?\"[A-Za-z0-9+/=]+' | cut -d'"' -f4)"
      [ -n "$out_b64" ] && printf '%s' "$out_b64" | base64 -d || true
      err_b64="$(echo "$out" | grep -oE '"err-data\": ?\"[A-Za-z0-9+/=]+' | cut -d'"' -f4)"
      [ -n "$err_b64" ] && printf '%s' "$err_b64" | base64 -d >&2 || true
      return "${rc:-0}"
    fi
    sleep 5
    i=$((i + 1))
  done
  echo "GUEST_EXEC_TIMEOUT: command did not exit within 300s"
  return 124
}

# Record read-only state evidence for one guest.
state_evidence() {
  local guest="$1"
  echo "--- $guest domifaddr agent ---"
  tower "sudo virsh domifaddr '$guest' --source agent 2>&1" | tee -a "$OUT_DIR/$guest-net.txt"
  echo "--- tower ip neigh for guest ip ---"
  tower "ip neigh show | grep -E '${2:-192\.168\.1\.}' || echo 'no arp entries'" | tee -a "$OUT_DIR/$guest-net.txt"
}

# net_repair <guest> <ip> <interface>
#   Diagnose, then DHCP renew; if still no IPv4, static-assign the documented
#   address. Returns 0 if the guest ends with the IPv4 configured; 1 otherwise.
net_repair() {
  local guest="$1" ip="$2" iface="$3"
  echo "=== [net-repair] $guest: pre-state ===" | tee "$OUT_DIR/$guest-net.txt"
  state_evidence "$guest"

  echo "=== [net-repair] $guest: in-guest diagnosis (guest-exec, read-only) ==="
  guest_exec "$guest" "ip -br addr show; ip route show; ls /etc/network/interfaces.d/ 2>/dev/null; cat /etc/network/interfaces 2>/dev/null | head -20; nmcli device status 2>/dev/null || true" |
    tee -a "$OUT_DIR/$guest-net.txt"

  echo "=== [net-repair] $guest: DHCP renew/bounce on $iface ==="
  guest_exec "$guest" "ip link set '$iface' down; ip link set '$iface' up; ifup '$iface' 2>/dev/null || nmcli con up '\$(nmcli -t -f NAME,DEVICE connection show 2>/dev/null | grep $iface | head -1 | cut -d: -f1)' 2>/dev/null || dhclient -v '$iface' 2>&1 | tail -5 || true" |
    tee -a "$OUT_DIR/$guest-net.txt"
  sleep 10

  if guest_exec "$guest" "ip -4 addr show '$iface' | grep -q 'inet '"; then
    echo "DHCP-RECOVERED: $guest has IPv4 after interface bounce" | tee -a "$OUT_DIR/$guest-net.txt"
  else
    echo "=== [net-repair] $guest: static assign $ip/24 gw 192.168.1.1 ==="
    guest_exec "$guest" "ip addr add '$ip'/24 dev '$iface' 2>&1; ip link set '$iface' up; ip route add default via 192.168.1.1 dev '$iface' 2>&1 || ip route replace default via 192.168.1.1 dev '$iface' 2>&1; ip -4 addr show '$iface'" |
      tee -a "$OUT_DIR/$guest-net.txt"
  fi

  echo "=== [net-repair] $guest: post-state ==="
  state_evidence "$guest"

  if guest_exec "$guest" "ip -4 addr show '$iface' | grep -q 'inet '" &&
    tower "ip neigh show | grep -q '$ip'"; then
    echo "NET-REPAIR OK: $guest has IPv4 $ip and tower ARP entry present" | tee -a "$OUT_DIR/$guest-net.txt"
    return 0
  fi
  echo "NET-REPAIR INCOMPLETE for $guest — see $OUT_DIR/$guest-net.txt" | tee -a "$OUT_DIR/$guest-net.txt"
  return 1
}

rc13=0 rc12=0
net_repair debian13 192.168.1.120 enp1s0 || rc13=$?
net_repair debian12 192.168.1.162 enp1s0 || rc12=$?

# If either guest now answers SSH from the runner, record that too.
for entry in "debian13 192.168.1.120" "debian12 192.168.1.162"; do
  set -- $entry
  guest="$1"
  ip="$2"
  if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_KNOWN_HOSTS" "$ip" "true" 2>/dev/null; then
    echo "SSH: $ip reachable from runner after net repair" | tee -a "$OUT_DIR/$guest-net.txt"
  else
    echo "SSH: $ip still not reachable from runner" | tee -a "$OUT_DIR/$guest-net.txt"
  fi
done

cat >"$OUT_DIR/net-repair.json" <<JSON
{"hypervisor":"tower","purpose":"debian13/debian12 in-guest network repair via guest-agent (issue #14)","stamp":"$STAMP","debian13_rc":$rc13,"debian12_rc":$rc12,"checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/net-repair.json"

if [ "$rc13" = "0" ]; then
  echo "=== debian13 NETWORK REPAIRED ==="
  exit 0
fi
echo "=== debian13 network repair incomplete (rc=$rc13) — see evidence ==="
exit "$rc13"
