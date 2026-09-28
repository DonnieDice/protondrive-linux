#!/bin/sh
# scripts/ci/vm-provision/guest/alpine-320-live-install.sh
#
# Runs as root in the Alpine 3.20.10 live environment of the transient
# alpine320-install domain (serial console session, issue #21 / parent #5).
# Network (eth0 192.168.1.157/24) was already brought up by the console
# bootstrap before this script runs; the payload blob (this script, the
# chroot script, and the Hermes public key) arrived over the LAN.
#
# Installs Alpine to /dev/vda in sys mode:
#   - persistent static LAN config: eth0 192.168.1.157/24 gw 192.168.1.1
#   - hostname alpine320
#   - sshd installed + enabled (setup-disk replicates world + runlevels)
#   - ERASE_DISKS + SWAP_SIZE=0 make setup-disk non-interactive:
#     vda1=/boot, vda2=/ (no swap)
#
# Emits INSTALL_DONE on success, INSTALL_FAILED on any error (consumed by
# the expect driver).
trap 'echo INSTALL_FAILED' EXIT
set -ex

echo "=== live-install start ==="
cat /etc/alpine-release
ip link show

# persistent network config (copied to the target by setup-disk)
cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address 192.168.1.157
	netmask 255.255.255.0
	gateway 192.168.1.1
EOF

# hostname
setup-hostname alpine320
hostname alpine320

# package sources: keep the ISO media repo, add the v3.22 network mirror
# (qemu-guest-agent is not on the standard ISO media)
grep -q 'dl-cdn.alpinelinux.org' /etc/apk/repositories || \
	printf 'https://dl-cdn.alpinelinux.org/alpine/v3.20/main\nhttps://dl-cdn.alpinelinux.org/alpine/v3.20/community\n' \
	>> /etc/apk/repositories
apk update

# sshd in the live env; enters the apk world so setup-disk installs it on
# the target too, and enables the default runlevel
setup-sshd -c openssh

# disk install (sys mode, BIOS/extlinux on the qcow2 via /dev/vda)
ERASE_DISKS=/dev/vda SWAP_SIZE=0 setup-disk -m sys /dev/vda

echo "INSTALL_DONE"
trap - EXIT
