#!/usr/bin/env bash
# scripts/ci/vm-provision/repair-vm-domain-disk.sh
#
# Authorized domain-disk repair for issue #14 (scope item 2: "If VM state must
# be inspected or repaired ... authorized host operations limited to what this
# assignment requires").
#
# Root cause (read-only evidence, inspection job 25655 / pipeline 2261):
#   virsh start debian13 failed with
#     "Path '/mnt/pool_two/domains/debian13/vdisk1.qcow2' is not accessible:
#      No such file or directory"   (guest-start job 24760 / pipeline 2180)
#   The domains share was migrated off pool_two (directory timestamps Sep 27
#   22:19); the real 32GB qcow2 lives at /mnt/user/domains/debian13/vdisk1.qcow2
#   — the same user-share path every working guest uses (alpine320, arch, ...).
#
# This script repairs exactly the disk <source file> path of exactly the
# guests the issue-#14 provisioning job needs — debian13 first, then debian12
# (only because the shared vm:provision:build-deps job provisions both hosts)
# — and starts them. No other guest is touched; no other mutation is made.
#
# Per guest the only mutations are:
#   1. virsh dumpxml <guest>  -> timestamped backup under /tmp on the tower
#   2. the one missing disk path string replaced with the verified real path
#      (virsh define with corrected XML; everything else byte-identical)
#   3. virsh start <guest>
# Guarded preconditions per guest (no mutation unless all hold):
#   - guest is shut off
#   - a configured disk path is missing on the tower
#   - the replacement path exists and qemu-img reports a virtual size >= 20GiB
# Read-only evidence is recorded before and after: virsh list --all,
# domblklist, domstate, ip neigh, and SSH reachability polls from the runner.
#
# Transport: the runner-mounted /root/.ssh config (alias: tower) — the same
# transport used by inspection job 25655 and guest-start job 24760.

set -uo pipefail

TOWER_HOST="${TOWER_HOST:-tower}"
OUT_DIR="${REPAIR_OUT_DIR:-repair-results}"
mkdir -p "$OUT_DIR"

VM_KNOWN_HOSTS="${CI_PROJECT_DIR:-.}/.vm-known-hosts"
: > "$VM_KNOWN_HOSTS"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$VM_KNOWN_HOSTS"

tower() { ssh $SSH_OPTS "$TOWER_HOST" "$@"; }
vm_ssh_ok() { ssh $SSH_OPTS -o ConnectTimeout=10 "$1" "true" 2>/dev/null; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

echo "=== [repair] tower identity ==="
tower "hostname; whoami; date -u" | tee "$OUT_DIR/identity.txt" || { echo "FATAL: cannot reach tower"; exit 1; }

echo "=== [repair] pre-state (read-only) ==="
tower "sudo virsh list --all; echo ---; sudo virsh domblklist debian13 2>&1; echo ---; sudo virsh domblklist debian12 2>&1" \
  | tee "$OUT_DIR/pre-state.txt"

# repair_and_start <guest> <real_disk> <ip>
#   Runs the guarded repair + start for one guest as a single remote script
#   (heredoc keeps all quoting on the remote side), then polls SSH
#   reachability from the runner. Returns 0 if the guest is running and
#   SSH-reachable, 1 on precondition/start failure, 3 if started but SSH
#   did not answer within the poll window.
repair_and_start() {
  local guest="$1" real_disk="$2" ip="$3" rc=0

  tower "sudo bash -s -- '$guest' '$real_disk' '$STAMP'" <<'REMOTE' 2>&1 | tee "$OUT_DIR/$guest-repair.txt"
set -u
guest="$1"; real_disk="$2"; stamp="$3"
state="$(sudo virsh domstate "$guest" 2>&1)" || { echo "DOMSTATE_FAIL: $state"; exit 1; }
echo "state: $state"
if [ "$state" != "shut off" ]; then
  echo "ALREADY_ACTIVE: $guest is not shut off — no repair attempted"
  exit 0
fi
sudo virsh dumpxml "$guest" | awk '
  /<disk / && /device=.disk./ { indisk=1 }
  indisk && /<source file=/ {
    if (match($0, /<source file=.([^'"'"']+)/)) { print substr($0, RSTART+14, RLENGTH-14) }
    indisk=0
  }' > "/tmp/$guest-configured-$stamp.txt"
missing=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  echo "configured disk path: $p"
  if [ ! -e "$p" ] && [ -z "$missing" ]; then missing="$p"; fi
done < "/tmp/$guest-configured-$stamp.txt"
if [ -z "$missing" ]; then
  echo "NO_MISSING_PATH: all configured disk paths exist — start only"
else
  echo "MISSING_PATH: $missing"
  if [ ! -f "$real_disk" ]; then
    echo "ABORT: replacement $real_disk does not exist (no mutation performed)"
    exit 1
  fi
  if ! qemu-img info "$real_disk" > "/tmp/$guest-qemuimg-$stamp.txt" 2>&1; then
    echo "ABORT: qemu-img info failed on $real_disk (no mutation performed)"; cat "/tmp/$guest-qemuimg-$stamp.txt"; exit 1
  fi
  cat "/tmp/$guest-qemuimg-$stamp.txt"
  vsize="$(awk '/^virtual size:/{for(i=1;i<=NF;i++) if($i+0>0 && $i ~ /^[0-9]+$/){print $i; exit}}' "/tmp/$guest-qemuimg-$stamp.txt")"
  echo "virtual size (GiB): ${vsize:-unparsed}"
  if [ -z "$vsize" ] || [ "$vsize" -lt 20 ]; then
    echo "ABORT: replacement disk virtual size < 20GiB (no mutation performed)"
    exit 1
  fi
  sudo virsh dumpxml "$guest" > "/tmp/$guest-xml-backup-$stamp.xml"
  sed "s|$missing|$real_disk|g" "/tmp/$guest-xml-backup-$stamp.xml" > "/tmp/$guest-xml-fixed-$stamp.xml"
  if cmp -s "/tmp/$guest-xml-backup-$stamp.xml" "/tmp/$guest-xml-fixed-$stamp.xml"; then
    echo "ABORT: sed produced no change — path string not found in XML (no mutation performed)"
    exit 1
  fi
  if ! sudo virsh define "/tmp/$guest-xml-fixed-$stamp.xml"; then
    echo "ABORT: virsh define failed (domain unchanged; backup kept)"
    exit 1
  fi
  echo "DEFINED: backup at /tmp/$guest-xml-backup-$stamp.xml"
  sudo virsh domblklist "$guest"
fi
if ! sudo virsh start "$guest"; then
  echo "START_FAIL: virsh start failed"
  sudo virsh dominfo "$guest"
  exit 1
fi
echo "STARTED: $guest"
exit 0
REMOTE
  rc="${PIPESTATUS[0]}"
  if [ "$rc" -ne 0 ]; then
    echo "=== $guest: remote repair/start incomplete (rc=$rc) — evidence in $OUT_DIR/$guest-repair.txt ==="
    return 1
  fi

  echo "=== [repair] $guest: waiting for SSH at $ip (from the runner) ==="
  local up=0 i
  for i in $(seq 1 40); do
    if vm_ssh_ok "$ip"; then up=1; echo "SSH: $ip reachable after attempt $i"; break; fi
    sleep 15
  done
  echo "$guest ssh_reachable=$up" | tee "$OUT_DIR/$guest-ssh.txt"
  if [ "$up" != "1" ]; then
    echo "$guest: started but not SSH-reachable within 600s — recording state for diagnosis."
    return 3
  fi
  return 0
}

rc13=0 rc12=0
repair_and_start debian13 /mnt/user/domains/debian13/vdisk1.qcow2 192.168.1.120 || rc13=$?
repair_and_start debian12 /mnt/user/domains/debian12/vdisk1.qcow2 192.168.1.162 || rc12=$?

echo "=== [repair] post-state (read-only evidence) ==="
tower "sudo virsh list --all; echo ---; sudo virsh domblklist debian13 2>&1; echo ---; sudo virsh domblklist debian12 2>&1; echo ---; ip neigh show | grep -E '192.168.1.120|192.168.1.162' || echo 'no arp entries for .120/.162'" \
  | tee "$OUT_DIR/post-state.txt"

cat > "$OUT_DIR/repair.json" <<JSON
{"hypervisor":"tower","purpose":"debian13/debian12 domain-disk path repair + start (issue #14)","xml_backup_stamp":"$STAMP","debian13_rc":$rc13,"debian12_rc":$rc12,"checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","ci_job":"${CI_JOB_ID:-0}","ci_pipeline":"${CI_PIPELINE_ID:-0}","ci_commit":"${CI_COMMIT_SHA:-local}"}
JSON
cat "$OUT_DIR/repair.json"

if [ "$rc13" = "0" ] && [ "$rc12" = "0" ]; then
  echo "=== REPAIR COMPLETE: both guests running and SSH-reachable ==="
  exit 0
fi
if [ "$rc13" = "0" ]; then
  echo "=== debian13 REPAIRED AND REACHABLE; debian12 not fully up (rc=$rc12) — see evidence ==="
  exit 4
fi
echo "=== debian13 repair/start incomplete (rc=$rc13) — see evidence ==="
exit "$rc13"
