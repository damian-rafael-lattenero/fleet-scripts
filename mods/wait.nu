# wait.nu — bounded readiness polling: the one retry shape a command needs
# when it must not return before a dependency answers.
#
# Nushell ships no "wait until". The fleet's honest alternatives are
# launchd's exit-75 retry (agent-brain/scripts/stack-up.nu) for boot-time
# work, and THIS for a command that has to block. The law: the deadline is
# MANDATORY (no unbounded loops — the reactive law), the probe is a closure
# called until it answers true (a predicate, its own timeout inside), and
# the interval is explicit — never a long blind sleep.

export def wait-until [
    deadline: duration   # total budget; the call answers false when it expires
    probe: closure       # {|| ... } -> bool: the readiness predicate
    --interval: duration = 500ms
]: nothing -> bool {
    let end: datetime = ((date now) + $deadline)
    mut ok: bool = false
    mut first: bool = true
    while (date now) < $end {
        if not $first { sleep $interval }
        $first = false
        if (do $probe) {
            $ok = true
            break
        }
    }
    $ok
}
