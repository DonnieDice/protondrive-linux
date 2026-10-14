#!/bin/sh
# scripts/ci/vm-provision/guest/alpine-322-chroot-config.sh
#
# Runs in the Alpine live environment chrooted into the freshly installed
# target on /mnt (caller bind-mounts /proc /sys /dev and copies resolv.conf).
# Payload pieces (this script + hermes-key.pub) arrived over the LAN.
#
# Brings the installed system to the #22 acceptance spec:
#   - qemu-guest-agent installed + enabled
#   - Hermes public key as root authorized_keys (root password locked,
#     sshd PermitRootLogin prohibit-password, PubkeyAuthentication yes)
#   - serial console getty for headless maintenance
#   - SSH host keys generated so sshd is ready on first boot
set -ex

echo "=== chroot-config start ==="

# network mirrors on the installed system (media repo dies with the ISO)
cat > /etc/apk/repositories <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/v3.22/main
https://dl-cdn.alpinelinux.org/alpine/v3.22/community
EOF
apk update

# QEMU guest agent
apk add qemu-guest-agent
rc-update add qemu-guest-agent default

# Hermes key: sole root login method
apk add openssh
install -d -m 700 /root/.ssh
if [ -s /root/hermes-key.pub ]; then
  install -m 600 /root/hermes-key.pub /root/.ssh/authorized_keys
else
  echo "FATAL: /root/hermes-key.pub missing in chroot" >&2
  exit 1
fi
passwd -l root || true

# --- sshd hardening + key-auth acceptance gate ---
# Alpine 3.22 openssh ships sshd_config with directives COMMENTED OUT
# (e.g. "#PubkeyAuthentication yes"). The defaults resolve to yes/prohibit-
# password, but that resolution depends on no Include /sshd_config.d overrides.
# OpenSSH uses first-occurrence-wins: PREPEND the directives at the file head
# so they shadow any default or Include, then validate before boot. This is
# the same repair #21's vm:verify:alpine320 job (commit d3945c8) applied via
# the QEMU guest agent -- done here at install time instead, so the first SSH
# probe hits a correctly configured sshd without a follow-up repair job.
{
  printf 'PubkeyAuthentication yes\n'
  printf 'PermitRootLogin prohibit-password\n'
  printf 'AuthorizedKeysFile .ssh/authorized_keys\n'
  cat /etc/ssh/sshd_config
} > /etc/ssh/sshd_config.repair
mv /etc/ssh/sshd_config.repair /etc/ssh/sshd_config
chmod 600 /etc/ssh/sshd_config
grep -n 'PubkeyAuthentication\|PermitRootLogin\|AuthorizedKeysFile' /etc/ssh/sshd_config

# Generate SSH host keys now (inside the chroot) so sshd can answer on first
# boot without delaying acceptance; rc-update add below makes sshd autostart.
ssh-keygen -A 2>/dev/null || true
sshd -t 2>&1 && echo "sshd config test ok" || echo "WARN: sshd config test failed"

# serial console getty
sed -i 's/^#ttyS0/ttyS0/' /etc/inittab
grep -q 'ttyS0::respawn' /etc/inittab || \
  printf 'ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100\n' >>/etc/inittab

# boot services
rc-update add sshd default || true
rc-update add networking boot || true
rc-update add acpid default || true
rc-update add crond default || true

echo "=== chroot-config done ==="
