#!/bin/sh
# scripts/ci/vm-provision/guest/alpine-322-live-install.sh
#
# Runs as root in the Alpine 3.22.4 live environment of the transient
# alpine322-install domain (serial console session, issue #22 / parent #6).
# Network (eth0 192.168.1.126/24) was already brought up by the console
# bootstrap before this script runs; the payload blob (this script, the
# chroot script, and the Hermes public key) arrived over the LAN.
#
# Installs Alpine to /dev/vda in sys mode:
#   - persistent static LAN config: eth0 192.168.1.126/24 gw 192.168.1.1
#   - hostname alpine322
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
cat >/etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address 192.168.1.126
	netmask 255.255.255.0
	gateway 192.168.1.1
EOF

# hostname
setup-hostname alpine322
hostname alpine322

# package sources: keep the ISO media repo, add the v3.22 network mirror
# (qemu-guest-agent is not on the standard ISO media)
grep -q 'dl-cdn.alpinelinux.org' /etc/apk/repositories ||
  printf 'https://dl-cdn.alpinelinux.org/alpine/v3.22/main\nhttps://dl-cdn.alpinelinux.org/alpine/v3.22/community\n' \
    >>/etc/apk/repositories
apk update

# sshd in the live env; enters the apk world so setup-disk installs it on
# the target too, and enables the default runlevel
# NOT setup-sshd: alpine-conf >=3.17 (Alpine 3.19+) prompts interactively
# for "Allow root ssh login?", which would hang the headless console driver
# (the #21 sibling proved the hang). apk + rc-update are fully
# non-interactive and setup-disk replicates both the apk world and the
# /etc/runlevels state onto the target.
apk add openssh
rc-update add sshd default

# disk install (sys mode, BIOS/extlinux on the qcow2 via /dev/vda)
ERASE_DISKS=/dev/vda SWAP_SIZE=0 setup-disk -m sys /dev/vda

echo "INSTALL_DONE"
trap - EXIT
