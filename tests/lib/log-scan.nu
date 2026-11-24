# log-scan.nu — the shared log sweep: a deploy log keeps older runs in the
# same file, only the CURRENT run speaks. Pure: lines in, lines out.
use std/assert
use ../../lib/log-scan.nu *

let log: list<string> = [
    "== run 1 =="
    "old failure"
    "== run 2 =="
    "ok"
]

# 1. the slice starts AT the last run marker, not after it.
assert equal (current-run $log '^== run') ["== run 2 ==" "ok"]

# 2. no marker at all: the whole log is the current run (a fresh file, or a
#    format we do not know yet — silence would hide the failure).
assert equal (current-run ["a" "b"] '^== run') ["a" "b"]

# 3. a single run: identical to the input.
assert equal (current-run ["== run 1 ==" "x"] '^== run') ["== run 1 ==" "x"]

# 4. the marker regex is the caller's: a different pattern keeps its own slice.
let two_markers: list<string> = ["--- start" "a" "=== other" "b"]
assert equal (current-run $two_markers '^--- start') ["--- start" "a" "=== other" "b"]
assert equal (current-run $two_markers '^=== ' ) ["=== other" "b"]

print "lib/log-scan ok"
