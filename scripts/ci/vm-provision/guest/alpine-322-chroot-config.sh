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
#     sshd PermitRootLogin prohibit-password)
#   - serial console getty for headless maintenance
set -ex

echo "=== chroot-config start ==="

# network mirrors on the installed system (media repo dies with the ISO)
cat >/etc/apk/repositories <<'EOF'
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
sed -i 's/^#\{0,1\}PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
grep -n 'PermitRootLogin' /etc/ssh/sshd_config || true

# serial console getty
sed -i 's/^#ttyS0/ttyS0/' /etc/inittab
grep -q 'ttyS0::respawn' /etc/inittab ||
  printf 'ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100\n' >>/etc/inittab

# boot services
rc-update add sshd default || true
rc-update add networking boot || true
rc-update add acpid default || true
rc-update add crond default || true

echo "=== chroot-config done ==="
