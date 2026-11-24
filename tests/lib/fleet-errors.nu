# test_fleet_errors.nu — the pure-core proofs for lib/fleet-errors.nu and
# lib/log-scan.nu: the error predicate, the stamp parse, the freshness rule
# (future stamps are never fresh) and the current-run sweep.
use std/assert
use ../../lib/fleet-errors.nu *
use ../../lib/log-scan.nu *

# 1. trim100 cuts at 100 chars, leaves short lines alone.
assert equal (trim100 "short") "short"
let long: string = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345"
assert greater ($long | str length) 100   # fixture is longer than the cut
assert equal (trim100 ($long + "TAIL") | str length) 100
assert equal (trim100 ($long + "TAIL")) ($long | str substring 0..99)

# 2. the stamp parse: a leading datetime parses, prose answers null.
assert equal ((line-stamp "2026-11-24 10:00:00 ERROR boom") | format date "%Y-%m-%d") "2026-11-24"
assert equal (line-stamp "no stamp here") null
assert equal (line-stamp "WARN 2026-11-24 ERROR") null

# 3. freshness: inside the window and never in the future.
let cutoff: datetime = ("2026-11-23 00:00:00" | into datetime)
let now: datetime = ("2026-11-25 00:00:00" | into datetime)
assert equal (is-fresh "2026-11-24 10:00:00 ERROR boom" $cutoff $now) true
assert equal (is-fresh "2026-11-22 10:00:00 ERROR old" $cutoff $now) false
assert equal (is-fresh "2026-11-26 10:00:00 ERROR future" $cutoff $now) false   # yesterday's late line
assert equal (is-fresh "unstamped ERROR" $cutoff $now) false

# 4. the error predicate: level tokens and failure markers only, never prose.
assert equal ("2026-11-24 10:00:00 ERROR boom" =~ $ERROR_MARKER) true
assert equal ("java.lang.Exception: boom" =~ $ERROR_MARKER) true
assert equal ("BUILD FAILED in 3s" =~ $ERROR_MARKER) true
assert equal (": fatal: not a git repo" =~ $ERROR_MARKER) true
assert equal ("✗ deploy broke" =~ $ERROR_MARKER) true
assert equal ("this error is prose" =~ $ERROR_MARKER) false
assert equal ("pong" =~ $ERROR_MARKER) false

# 5. the whole per-log answer from lines.
let lines: list<string> = [
    "2026-11-24 10:00:00 ERROR first"
    "plain prose mentioning error nothing"
    "2026-11-24 11:00:00 BUILD FAILED"
    "Exception ignored"
    "pong"
]
let scan: LogScan = (scan-lines "drill" $lines $cutoff $now)
assert equal $scan.log "drill"
assert equal $scan.errors 3
assert equal $scan.fresh 2
assert str contains $scan.last "Exception ignored"
# no errors at all: empty last, zero counters.
let quiet: LogScan = (scan-lines "quiet" ["pong" "all good"] $cutoff $now)
assert equal $quiet.errors 0
assert equal $quiet.last ""

# 6. the current-run sweep: only the last run's lines; a marker-less log is
#    all current; an empty log answers [].
let deploy: list<string> = [
    "==> run 1"
    "✗ old failure"
    "==> run 2"
    "✓ done"
]
assert equal (current-run $deploy '==>|^\[deploy\]') ["==> run 2" "✓ done"]
assert equal (current-run ["a" "b"] '==>') ["a" "b"]
assert equal (current-run [] '==>') []

print "test_fleet_errors ok"
