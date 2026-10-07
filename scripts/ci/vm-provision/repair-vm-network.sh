#!/usr/bin/env bash
# scripts/ci/vm-provision/repair-vm-network.sh
#
# Authorized network repair for issue #14 scope item 2: "If VM state must be
# inspected or repaired ... authorized host operations limited to what this
# assignment requires". Evidence chain: after the domain-disk repair (job
# 26734, pipeline 2297) both debian13 and debian12 boot the installed OS with
# a connected qemu guest-agent, but enp1s0 never acquires its documented IPv4
# (debian13 192.168.1.120 / debian12 192.168.1.162) and neither VM MAC
# appears in the tower br0 ARP table (read-only diag job 26943, issue #15
# note 12804). Without the guest network, vm:provision:build-deps and
# vm:verify:rust-toolchain cannot run — the routed execution dependency of
# parent #3.
#
# Transport: the runner-mounted /root/.ssh config (alias: tower) — the same
# transport used by jobs 24251, 25655, 26734, and 26943.
#
# Design note: the first iteration of this job (27577) proved the agent
# channel answers (domifaddr --source agent returns in-guest interface data)
# but guest-exec JSON marshaled across the runner->ssh->tower->sudo->virsh
# layers was mangled. This version keeps EVERYTHING tower-side: one
# `sudo bash -s` heredoc per guest (the exact pattern job 26734 used
# successfully) with the guest name and IP as positional arguments; all
# qemu-agent JSON is built and parsed inside that remote script.
#
# Mutations, ONLY through the connected guest-agent channel and ONLY on the
# two in-scope guests (debian13 first, then debian12, which the shared
# vm:provision:build-deps job also needs):
#   1. Read-only in-guest diagnosis via guest-exec (ip addr/route, resolv.conf,
#      NetworkManager state).
#   2. Least-invasive first: bring the interface up and request a DHCP lease
#      (nmcli connect, ifup, dhclient — first one that works).
#   3. If DHCP still yields no IPv4: runtime (non-persistent) static assignment
#      of the documented address + default route, nameserver left untouched
#      unless /etc/resolv.conf has none.
#   4. One ping of the LAN gateway from inside the guest so the hypervisor
#      bridge learns the guest MAC (evidence: tower ip neigh).
# No domain XML, disk, or host-network mutation; nothing persistent in the
# guest. Read-only state evidence (virsh domifaddr, ip neigh) recorded before
# and after; SSH reachability probed from the runner at the end.

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

echo "=== [net-repair] guest power state (read-only) ==="
tower "sudo virsh list --all" | tee "$OUT_DIR/virsh-list.txt"

# state_evidence <guest> <ip> — read-only domifaddr + ARP view from the tower.
state_evidence() {
  local guest="$1" ip="$2"
  echo "--- [$guest] virsh domifaddr --source agent ---"
  tower "sudo virsh domifaddr '$guest' --source agent 2>&1" | tee -a "$OUT_DIR/$guest-net.txt"
  echo "--- [$guest] tower ip neigh ($ip) ---"
  tower "ping -c 2 -W 2 '$ip' >/dev/null 2>&1; ip neigh show | grep -E '\\.$(printf '%s' "$ip" | cut -d. -f1-3)\\.' || echo 'no matching arp entries'" | tee -a "$OUT_DIR/$guest-net.txt"
}

# net_repair <guest> <ip> — full agent-channel repair sequence, one remote
# script per guest. Remote exit codes: 0 = guest has IPv4 on enp1s0;
# 1 = repair attempted but still no IPv4; 3 = guest-agent channel unusable.
net_repair() {
  local guest="$1" ip="$2"
  echo "=== [net-repair] $guest: pre-state (read-only) ===" | tee "$OUT_DIR/$guest-net.txt"
  state_evidence "$guest" "$ip"

  echo "=== [net-repair] $guest: agent-channel repair sequence ==="
  tower "sudo bash -s -- '$guest' '$ip'" <<'REMOTE' 2>&1 | tee -a "$OUT_DIR/$guest-net.txt"
set -u
guest="$1"
ip="$2"
iface=enp1s0
gw=192.168.1.1

# agent_exec <command> — run /bin/sh -c <command> in the guest as root through
# the qemu guest-agent (guest-exec + poll + base64-decoded output). The
# command text must not contain double quotes or backslashes (JSON safety).
agent_exec() {
  cmd="$1"
  json="{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/sh\",\"arg\":[\"-c\",\"$cmd\"],\"capture-output\":true}}"
  resp="$(sudo virsh qemu-agent-command "$guest" "$json" 2>&1)" || {
    echo "AGENT-CMD-FAIL: $resp"
    return 3
  }
  pid="$(printf '%s' "$resp" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p')"
  [ -n "$pid" ] || {
    echo "AGENT-NO-PID: $resp"
    return 3
  }
  i=0
  sresp=""
  while [ "$i" -lt 90 ]; do
    sjson="{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}"
    sresp="$(sudo virsh qemu-agent-command "$guest" "$sjson" 2>&1)" || {
      echo "AGENT-STATUS-FAIL: $sresp"
      return 3
    }
    case "$sresp" in
      *'"exited": true'* | *'"exited":true'*) break ;;
    esac
    sleep 2
    i=$((i + 1))
  done
  out="$(printf '%s' "$sresp" | sed -n 's/.*"out-data": *"\([A-Za-z0-9+/=]*\)".*/\1/p')"
  err="$(printf '%s' "$sresp" | sed -n 's/.*"err-data": *"\([A-Za-z0-9+/=]*\)".*/\1/p')"
  [ -n "$out" ] && printf '%s' "$out" | base64 -d
  [ -n "$err" ] && printf '%s' "$err" | base64 -d >&2
  rc="$(printf '%s' "$sresp" | sed -n 's/.*"exitcode": *\([0-9][0-9]*\).*/\1/p')"
  return "${rc:-1}"
}

has_ipv4() { agent_exec "ip -4 addr show $iface | grep -q inet"; }

echo "--- [$guest] in-guest diagnosis (read-only, via guest-agent) ---"
agent_exec "ip -br addr show; echo ---; ip route show; echo ---; head -5 /etc/resolv.conf 2>/dev/null; echo ---; nmcli device status 2>/dev/null || echo no-nmcli; echo ---; ls /etc/network/interfaces.d 2>/dev/null || true" ||
  echo "(diagnosis command rc=$?)"

if has_ipv4; then
  echo "IPv4-PRESENT: $guest already has IPv4 on $iface before repair"
else
  echo "--- [$guest] DHCP attempt: NM connect, interface bounce, ifup, dhclient ---"
  agent_exec "nmcli networking on 2>/dev/null; nmcli device connect $iface 2>/dev/null; ip link set $iface down; ip link set $iface up; ifup $iface 2>/dev/null; timeout 25 dhclient $iface 2>&1; true"
  sleep 5
  if has_ipv4; then
    echo "DHCP-RECOVERED: $guest has IPv4 on $iface after bounce/renew"
  fi
fi

if ! has_ipv4; then
  echo "--- [$guest] static fallback (runtime, non-persistent): $ip/24 via $gw ---"
  agent_exec "ip addr add $ip/24 dev $iface 2>/dev/null; ip link set $iface up; ip route replace default via $gw dev $iface 2>/dev/null; grep -q nameserver /etc/resolv.conf 2>/dev/null || echo nameserver $gw >> /etc/resolv.conf; true"
  sleep 3
  if has_ipv4; then
    echo "STATIC-APPLIED: $guest has $ip on $iface (runtime)"
  else
    echo "STATIC-FAILED: $guest still has no IPv4 on $iface"
  fi
fi

echo "--- [$guest] ARP presence: ping the LAN gateway from the guest ---"
agent_exec "ping -c 2 -W 2 $gw 2>&1 | tail -2; true"

echo "--- [$guest] final in-guest state (read-only) ---"
agent_exec "ip -br addr show $iface; ip route show; true"

if has_ipv4; then
  echo "GUEST-NET-OK: $guest has IPv4 on $iface"
  exit 0
fi
echo "GUEST-NET-FAILED: $guest has no IPv4 on $iface"
exit 1
REMOTE
  return "${PIPESTATUS[0]}"
}

rc13=0 rc12=0
net_repair debian13 192.168.1.120 || rc13=$?
net_repair debian12 192.168.1.162 || rc12=$?

echo "=== [net-repair] post-state (read-only) ==="
for entry in "debian13 192.168.1.120" "debian12 192.168.1.162"; do
  set -- $entry
  state_evidence "$1" "$2"
done

# SSH reachability from the runner (the path provision/verify jobs use).
for entry in "debian13 192.168.1.120" "debian12 192.168.1.162"; do
  set -- $entry
  guest="$1"
  ip="$2"
  if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_KNOWN_HOSTS" "$ip" "true" 2>/dev/null; then
    echo "SSH: $ip ($guest) reachable from runner after net repair" | tee -a "$OUT_DIR/$guest-net.txt"
  else
    echo "SSH: $ip ($guest) still not reachable from runner" | tee -a "$OUT_DIR/$guest-net.txt"
  fi
done

cat >"$OUT_DIR/net-repair.json" <<JSON
{"hypervisor":"tower","purpose":"debian13/debian12 in-guest network repair via guest-agent (issue #14)","method":"agent guest-exec: DHCP renew/bounce then runtime static fallback","stamp":"$STAMP","debian13_rc":$rc13,"debian12_rc":$rc12,"checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/net-repair.json"

if [ "$rc13" = "0" ]; then
  echo "=== debian13 NETWORK REPAIRED (rc12=$rc12) ==="
  exit 0
fi
echo "=== debian13 network repair incomplete (rc=$rc13) — see evidence ==="
exit "$rc13"
