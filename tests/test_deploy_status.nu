# test_deploy_status.nu — the pure-core proofs for lib/deploy-status.nu: the
# three predicate tables (state, cpu verdict, end marker), the pid parse and
# the last-line projection.
use std/assert
use ../lib/deploy-status.nu *

# 1. the state table: not loaded wins, then RUNNING, then idle.
assert equal (state-of false false) "not loaded"
assert equal (state-of false true) "not loaded"
assert equal (state-of true true) "RUNNING"
assert equal (state-of true false) "idle"

# 2. the pid parse: launchd's `pid = N` line, 0 when absent.
let probe: string = "gui/501/com.zcode.brain-deploy = {
	active count = 0
	state = running
	pid = 4242
}"
assert equal (pid-of $probe) 4242
assert equal (pid-of "state = running") 0
assert equal (pid-of "") 0

# 3. the cpu verdict: the boundary is the sum, exactly 5.0 is still STUCK.
assert equal (cpu-verdict 0.0 0.0) "STUCK SUSPECT cpu 0.0/0.0%"
assert equal (cpu-verdict 3.0 2.0) "STUCK SUSPECT cpu 3.0/2.0%"
assert equal (cpu-verdict 2.5 3.0) "RUNNING alive cpu 2.5/3.0%"

# 4. the end-marker table: ✗ convicts first, then done, then unknown.
assert equal (marker-of ["✗ boom" "all done"]) "last run FAILED"
assert equal (marker-of ["BUILD FAILED"]) "last run FAILED"
assert equal (marker-of ["work is done"]) "last run done"
assert equal (marker-of ["still building"]) "running or unknown end"
assert equal (marker-of []) "running or unknown end"

# 5. the last-line projection: "no log" when empty; a stack-trace token is
#    hard-wrapped so no space-separated piece exceeds 35 chars.
assert equal (last-line []) "no log"
let token: string = "com.zhipin.dashi.very.long.class.NameThatKeepsGoingAndGoing"
assert greater ($token | str length) 35
let wrapped: string = (last-line [$"Exception in ($token)"])
assert str contains $wrapped "Exception in"
let pieces: list<string> = ($wrapped | split row " ")
assert equal ($pieces | all {|p| ($p | str length) <= 35 }) true
assert equal ($wrapped | str replace -a " " "") ("Exceptionin" + $token)
print "test_deploy_status ok"
