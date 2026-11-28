# test_eval_numbers.nu — the metric rows, pinned: the plan's languages only
# (TypeScript stays out), zero-run languages skipped, the 5% gate math, and
# the rumbo population math. The edge (the sqlite reads and the POST) is the
# script's to prove.
#
# The fixtures are VERTICAL on purpose: three horizontal Writes of this file
# garbled mid-row (the long-line Write corruption the owner's law warns
# about), and the write-time oracle caught each one before any run.
use std/assert
use ../../lib/eval-numbers.nu *

# ── the language-week cells, built by hand: the fixture records garbled four
# Writes in a row, so the rows come from short builder closures instead ──
def cell [lang: string, runs: int, fails: int]: nothing -> record {
    {
        week: '2026-W47'
        monday: '11-16'
        lang: $lang
        writes: 100
        oracle_runs: $runs
        oracle_fails: $fails
        law_denials: 3
        denials_per_1000_writes: 30.0
    }
}

def fixture-cells []: nothing -> table {
    [
        (cell 'nu' 40 2)
        (cell 'kt' 8 3)
        (cell 'ts' 4 0)
        (cell 'hs' 0 0)
    ]
}

# ── first-pass: the languages, the skip, the gate math ──
let rows: list<MetricRun> = (first-pass-rows (fixture-cells) '2026-W47')
assert equal ($rows | length) 2 'ts stays out (plan) and zero-run languages are skipped'
assert equal ($rows | get suite) [first-pass-nu first-pass-kt]
assert equal ($rows | get 0.passed) 38
assert equal ($rows | get 0.total) 40
assert equal ($rows | get 0.ok) true
assert equal ($rows | get 0.gate) 0.95
assert equal ($rows | get 1.passed) 5
assert equal ($rows | get 1.total) 8
assert equal ($rows | get 1.ok) false '3 of 8 is above the 5% gate'
assert ($rows | get 0.detail.definition | str contains 'ISO week')

# ── rumbo: the population math ──
def fixture-turns []: nothing -> table {
    [
        {sid: 'a', reason: 'cancelled', n: 10}
        {sid: 'b', reason: 'cancelled', n: 6}
        {sid: 'c', reason: 'success', n: 4}
        {sid: 'd', reason: 'success', n: 30}
        {sid: 'e', reason: 'success', n: 30}
    ]
}

let r: MetricRun = (rumbo-row (fixture-turns))
assert equal $r.total 5
assert equal $r.passed 3
assert equal $r.detail.cancelled 2
assert equal $r.detail.cancels_per_100 40.0
assert equal $r.detail.wasted_steps_pct 20.0
assert equal $r.gate 0.0
assert equal $r.ok true 'informational until the owner sets the target'

# an empty population: zeros, never a crash
let empty: MetricRun = (rumbo-row [])
assert equal $empty.total 0
assert equal $empty.detail.cancels_per_100 0.0
assert equal $empty.detail.wasted_steps_pct 0.0

print 'test_eval_numbers ok'
