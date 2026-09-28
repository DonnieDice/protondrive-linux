#!/usr/bin/env expect -f
# scripts/ci/vm-provision/el10-console.tcl
#
# Serial-console driver for the CentOS Stream 10 kickstart install of issue
# #19 (parent #11). Runs ON THE GITLAB RUNNER inside a pty (the CI job shell
# allocates one), reaching the guest's serial console through tower:
#
#   ssh -tt tower "sudo virsh console el10-install --force"
#
# (the alpine322 pattern from issue #22; tower has no expect binary).
#
# Anaconda is fully driven by the kickstart fetched over the LAN, so this
# driver mostly watches: it confirms the installer starts, catches early
# kernel/installer failures, waits for the kickstart completion and the
# final reboot, and enforces the time budget.
#
# argv: <transient-guest> <total_budget_secs>
#
# NOTE on Tcl quoting: expect patterns are ALWAYS brace-quoted
# (e.g. {([0-9a-f]{32})}). A double-quoted pattern string makes Tcl run
# command substitution on [ ... ] inside it - the exact bug that killed
# job 25904 (alpine322) at its md5 check line.
set timeout 10
log_user 1

set guest  [lindex $argv 0]
set budget [lindex $argv 1]
if {$budget eq ""} { set budget 3000 }
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

# --- installer boot ---------------------------------------------------------
# kernel + Anaconda stage2 load from the DVD can take several minutes on this
# storage; 900s is generous but still bounded.
wait_for {Starting installer, one moment} 900

# --- kickstart-driven install ----------------------------------------------
# Anaconda logs progress lines (anaconda: ... scripts, packages at N/M).
# A fatal installer error aborts early; otherwise wait for the completion
# banner. CentOS Stream 10 prints "Installation complete" (kickstart %post
# done) before rebooting.
set timeout 300
expect {
	{Installation complete} { }
	{Pane is dead} { die "anaconda pane died (installer error)" }
	{Traceback (most recent call last)} { die "anaconda traceback" }
	eof { die "console EOF during install" }
	timeout {
		if {[remaining] > 0} {
			# keep watching under the global budget
			exp_continue
		} else {
			die "global budget exhausted during kickstart"
		}
	}
}

# --- reboot -----------------------------------------------------------------
# kickstart reboots the guest (on_reboot=destroy on the transient domain):
# the console closes. Give the domain time to power off; the CI driver then
# undefines it. virsh prints the disconnect notice.
set timeout 180
expect {
	{Domain $guest} { }
	eof { }
	timeout { puts "WARN: no explicit domain shutdown notice on console" }
}
after 5000
close
puts "\nEXPECT-CONSOLE-COMPLETE"
exit 0
