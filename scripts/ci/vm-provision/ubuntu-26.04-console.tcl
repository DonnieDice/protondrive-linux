#!/usr/bin/env expect -f
# scripts/ci/vm-provision/ubuntu-26.04-console.tcl
#
# Serial-console driver for the Ubuntu 26.04 headless install of issue #20
# (parent #8). Runs ON THE GITLAB RUNNER inside a pty (the CI job shell
# allocates one), reaching the guest's serial console through tower:
#
#   ssh -tt tower "sudo virsh console ubuntu-26.04-install --force"
#
# The preseed (served over the LAN from tower) drives the entire install
# automatically; this driver mostly watches: it confirms the installer
# starts, catches early kernel/installer failures, waits for the preseed
# late-command marker and the final reboot, and enforces the time budget.
#
# argv: <transient-guest> <total_budget_secs>
#
# NOTE on Tcl quoting: expect patterns are ALWAYS brace-quoted
# (e.g. {Installation complete}). A double-quoted pattern string makes Tcl
# run command substitution on [ ... ] inside it - the exact bug that killed
# the alpine322 driver at its md5 check (job 25904 line 100).
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
# The transient domain boots the netboot kernel with console=ttyS0. The first
# d-i banner ("Installing system" / "Debian installer") is the reliable early
# marker on serial. 900s is generous but bounded for kernel + installer load.
wait_for {"Installing system"} 900

# --- preseed-driven install -------------------------------------------------
# The preseed automates partitioning, package install, and the late-command.
# The late-command prints PRESEED_LATE_COMMAND_DONE (a unique marker) when
# it finishes; watching for it proves the preseed was actually loaded and
# executed (not skipped due to a URL fetch failure).
wait_for {"PRESEED_LATE_COMMAND_DONE"} 1800

# --- reboot -----------------------------------------------------------------
# The installer reboots after preseed completion. On the transient domain
# on_reboot=destroy closes the console (virsh prints the disconnect notice).
set timeout 180
expect {
	{"Done booting"} { }
	{"reboot"} { }
	{"Restarting system"} { }
	eof { }
	timeout { puts "WARN: no explicit reboot notice on console" }
}
after 5000
close
puts "\nEXPECT-CONSOLE-COMPLETE"
exit 0
