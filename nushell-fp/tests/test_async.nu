# test_async.nu — assertions for mods/async.nu (job applicative).
# Order: traverse-jobs (structure order → crash reporting → timeout) →
# record filling → apply-async (the kap .with chain).
use std/assert
use ../mods/async.nu *
use ../mods/currying.nu *

# ── traverse-jobs: structure order is restored, arrival order is racy ─────
assert equal ([{|| 10}, {|| 20}, {|| 30}] | traverse-jobs) [10 20 30]
# a slow FIRST job still lands first (order restored by index, not arrival)
assert equal ([{|| sleep 200ms; 2}, {|| 1}] | traverse-jobs) [2 1]
# empty input is the empty list
assert equal ([] | traverse-jobs) []

# ── crashes report through the mailbox — no silent hang, honest error ─────
# (learned live: the 355-file agent hang; the error rides the same mailbox
# and rethrows after collection)
let exploded: any = (try {
    [{|| 1}, {|| error make {msg: "boom element"}}, {|| 3}] | traverse-jobs
} catch {|e| $e.msg})
assert equal $exploded "nushell-fp traverse-jobs: failed elements — 1: boom element"
# EVERY crashed element is named, in structure order (accumulation law)
let multi: any = (try {
    [{|| error make {msg: e1}}, {|| 2}, {|| error make {msg: e3}}] | traverse-jobs
} catch {|e| $e.msg})
assert equal $multi "nushell-fp traverse-jobs: failed elements — 0: e1; 2: e3"

# ── timeout is the failure signal: jobs killed, the error is honest ───────
let timedOut: any = (try {
    [{|| sleep 2sec; 1}] | traverse-jobs --timeout 150ms
} catch {|e| $e.msg})
assert equal $timedOut "nushell-fp traverse-jobs: timeout — a job never finished"
# give the killed job's dying catch-send time to land, then prove the next
# call is clean — the per-call tag keeps the stale message out (regression:
# this exact sequence poisoned the mailbox before tag isolation)
sleep 100ms
assert equal ([{|| 1}, {|| 2}] | traverse-jobs) [1 2]

# ── build-record-jobs: every field a job; the record waits for the last ───
assert equal ({a: {|| 1}, b: {|| 2}} | build-record-jobs) {a: 1, b: 2}
# a slow field still fills — the structure exists when the last one lands
assert equal ({fast: {|| "x"}, slow: {|| sleep 150ms; "y"}} | build-record-jobs) {fast: x, slow: y}
# the empty record is the empty record (not the empty list — transpose edge)
assert equal ({} | build-record-jobs) {}

# ── apply-async: concurrent deferred args feed a curried closure ──────────
# (kap's `.with(Kap { ... })` chain in ONE call)
assert equal ([{|| 10}, {|| 3}] | apply-async (curry2 {|a: int, b: int| $a - $b})) 7
assert equal ([{|| 1}, {|| 2}, {|| 3}] | apply-async (curry3 {|a: int, b: int, c: int| $a * 100 + $b * 10 + $c})) 123

print "test_async ok"
