#!/usr/bin/env expect -f
# scripts/ci/vm-provision/ubuntu-26.04-console.tcl
#
# Serial-console driver for the Ubuntu 26.04 headless install of issue #20
# (parent #8). Runs ON THE GITLAB RUNNER inside a pty (the CI job shell
# allocates one), reaching the guest's serial console through tower:
#
#   ssh -tt tower "sudo virsh console ubuntu2604-install --force"
#
# The Subiquity autoinstall user-data (served over the LAN from tower) drives
# the entire install automatically; this driver mostly watches: it confirms
# the installer starts, catches early kernel/installer failures, waits for the
# late-command marker and the final reboot, and enforces the time budget.
#
# argv: <transient-guest> <total_budget_secs>
#
# NOTE on Tcl quoting: expect patterns are ALWAYS brace-quoted
# (e.g. {Installation complete}). A double-quoted pattern string makes Tcl
# run command substitution on [ ... ] inside it - the exact bug that killed
# the alpine322 driver at its md5 check (job 25904 line 100).
# EQUALLY IMPORTANT: the pattern must NOT itself contain double quotes.
# wait_for {"Linux version"} (job 58203) matched nothing because the glob
# required literal quote characters around the phrase - the session died at
# exactly 1800s while the kernel banner had been visible within one second.
# Patterns below are brace-quoted with NO embedded quotes.
set timeout 10
log_user 1
if {[info exists env(CONSOLE_LOG)]} {
	log_file -noappend $env(CONSOLE_LOG)
}

set guest  [lindex $argv 0]
set budget [lindex $argv 1]
if {$budget eq ""} { set budget 3600 }
set deadline [expr {[clock seconds] + $budget}]

proc remaining {} { global deadline; return [expr {$deadline - [clock seconds]}] }
proc die {msg} { puts "\nEXPECT-FATAL: $msg"; exit 2 }

# Drain console output until the pattern appears or the wait budget dies.
proc wait_for {pattern secs} {
	set ::timeout $secs
	expect {
		$pattern { return 1 }
		timeout { die "timeout waiting for: $pattern" }
		eof     { die "console EOF waiting for: $pattern" }
	}
}

# ssh -tt: force a pty on tower's side too (job 25780 failed without it).
spawn ssh -tt -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
	-o UserKnownHostsFile=$env(VM_KNOWN_HOSTS) tower \
	"sudo virsh console $guest --force"

# --- installer boot --------------------------------------------------------
# The transient domain boots the live kernel with console=ttyS0. The Ubuntu
# 26.04 DESKTOP live image's serial output is the kernel boot log (no installer
# banner); Subiquity writes its progress to the console once cloud-init
# consumes the nocloud-net seed. We confirm two things on serial:
#   (a) the kernel boots (the Linux version line proves the live kernel+initrd
#       loaded and that the serial console path is wired), and
#   (b) the autoinstall late-command completion marker AUTOINSTALL_LATE_COMMAND_DONE
#       (proving the seed was fetched and Subiquity actually ran).
# Waiting on a graphic-installer banner ("Ubuntu 26.04") is unreliable on this
# image - job 57074 sat for 30 min with the disk untouched because Subiquity
# never received a config and the banner never appeared.
wait_for {Linux version} 1800

# --- autoinstall-driven install ---------------------------------------------
wait_for {AUTOINSTALL_LATE_COMMAND_DONE} 2400

# --- reboot -----------------------------------------------------------------
# The installer reboots after autoinstall completion. On the transient domain
# on_reboot=destroy closes the console (virsh prints the disconnect notice).
set timeout 180
expect {
	{Done booting} { }
	{rebooting} { }
	{Restarting system} { }
	eof { }
	timeout { puts "WARN: no explicit reboot notice on console" }
}
after 5000
close
puts "\nEXPECT-CONSOLE-COMPLETE"
exit 0
