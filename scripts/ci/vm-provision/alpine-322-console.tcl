#!/usr/bin/env expect -f
# scripts/ci/vm-provision/alpine-322-console.tcl
#
# Serial-console driver for the Alpine 3.22 install of issue #22 (parent #6).
# Runs ON THE GITLAB RUNNER inside a pty (the CI job allocates it), not on the
# tower host: tower has no expect binary (job 25177 failed rc=127 at exactly
# this point). The runner connects the pty through tower with:
#
#   ssh -tt tower "sudo virsh console alpine322-install --force"
#
# so the expect process on the runner drives the guest's serial console over
# the SSH transport. argv (all required):
#   <guest> <payload_port> <payload_md5> <total_budget_secs>
#
# Flow (the transient domain boots the ISO kernel directly with
# console=ttyS0,115200; Alpine's initramfs setup_inittab_console() spawns a
# getty for every console= param, so a login: prompt appears on serial):
#   1. wait for the live env's login: prompt; log in as root (no password)
#   2. bring up eth0 with the static IP + default route
#   3. start an nc listener; print the NC_READY marker (the CI job greps the
#      console log for it and pushes the payload bundle over the LAN)
#   4. verify the payload md5, explode it
#   5. run the live install (setup-disk), watch for INSTALL_DONE
#   6. chroot post-config, watch for CHROOT_DONE
#   7. power the guest off
#
# No secret material crosses this console: the workforce key's public half
# arrives inside the LAN payload; the private half never leaves the runner.
set timeout 10
log_user 1

set guest    [lindex $argv 0]
set port     [lindex $argv 1]
set paymd5   [lindex $argv 2]
set budget   [lindex $argv 3]
set deadline [expr {[clock seconds] + $budget}]

proc remaining {} { global deadline; return [expr {$deadline - [clock seconds]}] }
proc die {msg} { puts "\nEXPECT-FATAL: $msg"; exit 2 }

# The transient domain may already be mid-boot from a prior attempt: after
# spawn, drain whatever the console emits until the pattern or timeout.
proc wait_for {pattern secs} {
	set ::timeout $secs
	expect {
		$pattern { return 1 }
		timeout { die "timeout waiting for: $pattern" }
		eof     { die "console EOF waiting for: $pattern" }
	}
}

proc at_prompt {} {
	set ::timeout 20
	expect {
		-re "(^|\n|~ )# $" {}
		timeout { die "no shell prompt" }
	}
}

spawn ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
	-o UserKnownHostsFile=$env(VM_KNOWN_HOSTS) tower \
	"sudo virsh console $guest --force"

# --- login on the serial getty --------------------------------------------
# live env: root has no password; pressing enter on the login prompt is
# sufficient (getty asks for login name, root logs straight in)
wait_for "login:" 300
after 1000
send "root\r"

# --- static network in the live env ----------------------------------------
after 2000
send "ip addr add 192.168.1.126/24 dev eth0 && ip link set eth0 up\r"
send "ip route add default via 192.168.1.1\r"
after 1000
send "ip -4 addr show eth0 | grep inet\r"

# --- payload listener --------------------------------------------------------
# marker split into two sent halves so the echo of the command cannot match
# the grep the CI job runs against the console log
send "nc -l -p $port > /tmp/payload.tgz &\r"
after 500
send "echo NC_RE\"\"ADY\r"
wait_for "NC_READY" 120

# (the CI job pushes the bundle now; nc exits when the sender closes)
send "echo waiting-for-payload\r"

# --- verify + explode payload -----------------------------------------------
# nc exits promptly on sender close; the /tmp/payload.tgz appears in ls
set timeout 900
expect {
	-re "nc.*exit|payload.*$" {}
	timeout { die "payload transfer window exceeded" }
}
send "md5sum /tmp/payload.tgz\r"
expect -re "([0-9a-f]{32})"
if {$paymd5 ne $expect_out(1,string)} {
	send "echo MD5_MISMATCH\r"
	die "payload md5 mismatch (expected $paymd5)"
}
send "echo MD5_OK\r"
send "tar -xzf /tmp/payload.tgz -C /root && ls -la /root\r"
at_prompt
send "chmod +x /root/live-install.sh /root/chroot-config.sh\r"
at_prompt

# --- live install -------------------------------------------------------------
send "sh /root/live-install.sh; echo LIVE_RC=\$?\r"
set timeout 1500
expect {
	"INSTALL_DONE" {}
	"INSTALL_FAILED" { die "live-install reported INSTALL_FAILED" }
	-re "LIVE_RC=[1-9]" { die "live-install exited nonzero" }
	timeout { die "timeout during setup-disk" }
}

# --- chroot post-config --------------------------------------------------------
send "mount /dev/vda2 /mnt\r"
after 1000
send "mount -t proc proc /mnt/proc && mount --rbind /sys /mnt/sys && mount --rbind /dev /mnt/dev\r"
after 1000
send "cp -L /etc/resolv.conf /mnt/etc/ && cp /root/chroot-config.sh /root/hermes-key.pub /mnt/root/\r"
after 1000
send "chroot /mnt sh /root/chroot-config.sh; echo CHROOT_RC=\$?\r"
set timeout 1200
expect {
	"chroot-config done" {}
	-re "CHROOT_RC=[1-9]" { die "chroot-config exited nonzero" }
	timeout { die "timeout during chroot-config" }
}
send "umount -R /mnt/proc /mnt/sys /mnt/dev 2>/dev/null; umount /mnt\r"
after 3000

# --- poweroff -------------------------------------------------------------------
send "poweroff\r"
set timeout 120
expect {
	"Power down" {}
	"shut off" {}
	-re "The system is going down" {}
	timeout { puts "WARN: no explicit poweroff confirmation on console" }
}
after 15000
close
puts "\nEXPECT-CONSOLE-COMPLETE"
exit 0
